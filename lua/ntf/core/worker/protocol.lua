local M = {}

--- @class NtfWorkerMutation : NtfMutantSplice one mutation to splice into the module under test
--- @field path string normalized absolute path of the file to mutate

--- @class NtfWorkerPayload parameters for one worker process
--- @field file string spec file path
--- @field node_id string leaf id to run
--- @field names string[] the name chain the run planned at that id, which a diverged tree is answered with
--- @field leaves_count integer how many tests the file declared when the run was planned
--- @field test_hook string? Lua module path providing setup/teardown
--- @field process_hook string? Lua module path providing the setup this process runs before it loads a spec
--- @field coverage boolean
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

local PAYLOAD_ENV = "_NTF_WORKER_PAYLOAD"
local BEGIN = "<<<NTF_JSON:%s>>>"
local END = "<<<END_NTF_JSON:%s>>>"

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

--- @return NtfWorkerPayload the payload the controller passed in
function M.payload()
  return vim.json.decode(vim.env[PAYLOAD_ENV])
end

-- WHY: `arg` is not populated for the `-c "luafile"` launch worker/init.lua
-- explains, so parameters reach a worker through its environment.
-- NOT: passing them as script arguments read from `arg`.
--- @param payload NtfWorkerPayload
--- @return table<string, string> the environment that carries `payload` to a worker
function M.env(payload)
  return { [PAYLOAD_ENV] = vim.json.encode(payload) }
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
