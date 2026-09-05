local write = require("ntf.core.write")

local M = {}

--- @class NtfWorkerMutation : NtfMutantSplice one mutation to splice into the module under test
--- @field path string normalized absolute path of the file to mutate

--- @class NtfWorkerLeaf one leaf a worker is asked to run, named the way the run planned it
--- @field file string spec file path
--- @field node_id string leaf id to run
--- @field names string[] the name chain the run planned at that id, which a diverged tree is answered with
--- @field leaves_count integer how many tests the file declared when the run was planned

--- @class NtfWorkerTrial : NtfWorkerLeaf one leaf a mutant is tried against
--- @field budget_ms integer ms the leaf gets before the run kills the worker over it

--- @class NtfWorkerMutantJob one mutant and the leaves it is tried against, cheapest first
--- @field index integer the task the controller reads this job's events as
--- @field mutation NtfWorkerMutation
--- @field trials NtfWorkerTrial[]

--- @class NtfWorkerPayload parameters for one worker process
--- @field leaf NtfWorkerLeaf? the one leaf to run, for a worker the run gave a test
--- @field mutants NtfWorkerMutantJob[]? the mutants to take one after another, for a worker the run gave a chunk of them
--- @field test_hook string? Lua module path providing setup/teardown
--- @field process_hook string? Lua module path providing the setup this process runs before it loads a spec
--- @field coverage boolean? measure line coverage, for a worker the run gave a test
--- @field coverage_excludes string[]? absolute dir prefixes to exclude
--- @field mutation NtfWorkerMutation? apply this mutation when the module is required
--- @field cwd string working directory shared with the controller
--- @field watchdog_ms integer? kill this process after this long, whatever became of the run (absent when the run is untimed)
--- @field nonce string the suffix of the markers this worker's result block is written with

--- @class NtfWorkerResult the block a worker emits as its last stdout write
--- @field results NtfResult[]? per-leaf results (absent when the spec failed to load)
--- @field coverage table? per-file line hit counts (when coverage was measured)
--- @field mutation_applied boolean? whether the mutated module was actually loaded (mutation runs only)
--- @field load_error string? load failure message
--- @field file string? spec file path (set alongside load_error)

--- @class NtfWorkerEvent one line a worker writes as it works through its mutants
--- @field type "begin"|"verdict"
--- @field index integer the task the controller reads it as
--- @field trial integer? which of the mutant's trials began
--- @field status ("killed"|"survived"|"not_applied")? what the mutant came to
--- @field killed_by string? full name of the test that detected it
--- @field retried string[]? full names of the tests a kill was taken back from, absent where none was

local PAYLOAD_ENV = "_NTF_WORKER_PAYLOAD"
local PAYLOAD_FILE = "@"
local BEGIN = "<<<NTF_JSON:%s>>>"
local END = "<<<END_NTF_JSON:%s>>>"
local EVENT = "<<<NTF_EVENT:%s>>>"

--- @param nonce string the nonce of the worker whose block is written or read
--- @return string # the marker that opens that worker's block
--- @return string # the marker that closes it
local function markers(nonce)
  return BEGIN:format(nonce), END:format(nonce)
end

--- @return string # the marker nonce for one worker, which nothing that worker runs can guess
function M.nonce()
  local bytes = assert(vim.uv.random(16))
  return (bytes:gsub(".", function(byte)
    return ("%02x"):format(byte:byte())
  end))
end

-- WHY: `M.parse` splits a worker's stdout at the first marker pair and the
-- controller keeps what comes before it as the test's own output, so this must
-- be the last stdout write of the worker.
-- NOT: emitting a partial result early and a final one later; the second block
-- would land inside the first one's span.
--- @param result NtfWorkerResult
--- @param nonce string the nonce the controller drew for this worker
function M.emit(result, nonce)
  local begin_marker, end_marker = markers(nonce)
  io.stdout:write("\n" .. begin_marker .. "\n")
  io.stdout:write(vim.json.encode(result))
  io.stdout:write("\n" .. end_marker .. "\n")
end

--- @param event NtfWorkerEvent
--- @param nonce string the nonce the controller drew for this worker
function M.emit_event(event, nonce)
  io.stdout:write("\n" .. EVENT:format(nonce) .. vim.json.encode(event) .. "\n")
  io.stdout:flush()
end

--- @param nonce string the nonce the controller drew for that worker
--- @return fun(data: string?): NtfWorkerEvent[] # the events the writes fed to it so far have completed a line of
function M.event_reader(nonce)
  local marker = EVENT:format(nonce)
  local buffer = ""
  return function(data)
    buffer = buffer .. (data or "")
    local events = {}
    while true do
      local line_end = buffer:find("\n", 1, true)
      if not line_end then
        return events
      end
      local line = buffer:sub(1, line_end - 1)
      buffer = buffer:sub(line_end + 1)
      if line:sub(1, #marker) == marker then
        local ok, decoded = pcall(vim.json.decode, line:sub(#marker + 1))
        if ok then
          table.insert(events, decoded)
        end
      end
    end
  end
end

--- @return NtfWorkerPayload the payload the controller passed in
function M.payload()
  local value = vim.env[PAYLOAD_ENV]
  if value:sub(1, #PAYLOAD_FILE) ~= PAYLOAD_FILE then
    return vim.json.decode(value)
  end
  local file = value:sub(#PAYLOAD_FILE + 1)
  local handle = assert(io.open(file, "r"))
  local blob = handle:read("*a")
  handle:close()
  os.remove(file)
  return vim.json.decode(blob)
end

-- WHY: `arg` is not populated for the `-c "luafile"` launch worker/init.lua
-- explains, so parameters reach a worker through its environment.
-- NOT: passing them as script arguments read from `arg`.
--- @param payload NtfWorkerPayload
--- @param file string? a file to leave the payload in for the worker to read and delete, for one no environment block holds
--- @return table<string, string> the environment that carries `payload` to a worker
function M.env(payload, file)
  local encoded = vim.json.encode(payload)
  if not file then
    return { [PAYLOAD_ENV] = encoded }
  end
  write.file(file, encoded)
  return { [PAYLOAD_ENV] = PAYLOAD_FILE .. file }
end

--- @param stdout string? a worker's stdout
--- @param nonce string the nonce the controller drew for that worker
--- @return NtfWorkerResult? the decoded result block, if the stdout carries one written with that nonce
function M.parse(stdout, nonce)
  if not stdout then
    return nil
  end
  local begin_marker, end_marker = markers(nonce)
  local from = stdout:find(begin_marker, 1, true)
  local to = stdout:find(end_marker, 1, true)
  if not from or not to then
    return nil
  end
  local json = stdout:sub(from + #begin_marker, to - 1)
  local ok, decoded = pcall(vim.json.decode, json)
  if not ok then
    return nil
  end
  return decoded
end

--- @param stdout string?
--- @param stderr string?
--- @param nonce string the nonce the controller drew for that worker
--- @return string
function M.captured_output(stdout, stderr, nonce)
  local begin_marker = markers(nonce)
  local from = stdout and stdout:find(begin_marker, 1, true)
  local out = stdout and (from and stdout:sub(1, from - 1) or stdout) or ""
  local parts = {}
  for _, blob in ipairs({ out, stderr or "" }) do
    blob = blob:gsub("\n$", "")
    if blob ~= "" then
      table.insert(parts, blob)
    end
  end
  return table.concat(parts, "\n")
end

return M
