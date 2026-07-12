local M = {}

--- @class NtfWorkerMutation : NtfMutantSplice one mutation to splice into the module under test
--- @field path string normalized absolute path of the file to mutate

--- @class NtfWorkerPayload parameters for one worker process
--- @field file string spec file path
--- @field node_id string leaf id to run
--- @field test_hook string? Lua module path providing setup/teardown
--- @field coverage boolean
--- @field coverage_excludes string[]? absolute dir prefixes to exclude
--- @field mutation NtfWorkerMutation? apply this mutation when the module is required
--- @field cwd string working directory shared with the controller

--- @class NtfWorkerResult the block a worker emits as its last stdout write
--- @field results NtfResult[]? per-leaf results (absent when the spec failed to load)
--- @field coverage table? per-file line hit counts (when coverage was measured)
--- @field mutation_applied boolean? whether the mutated module was actually loaded (mutation runs only)
--- @field load_error string? load failure message
--- @field file string? spec file path (set alongside load_error)

local PAYLOAD_ENV = "_NTF_WORKER_PAYLOAD"
local BEGIN = "<<<NTF_JSON>>>"
local END = "<<<END_NTF_JSON>>>"

--- Worker side: write the result block. Must be the last stdout write; the
--- controller treats everything before the marker as the test's own output.
--- @param result NtfWorkerResult
function M.emit(result)
  io.stdout:write("\n" .. BEGIN .. "\n")
  io.stdout:write(vim.json.encode(result))
  io.stdout:write("\n" .. END .. "\n")
end

--- Worker side: decode the payload the controller passed in.
--- @return NtfWorkerPayload
function M.payload()
  return vim.json.decode(vim.env[PAYLOAD_ENV])
end

--- Controller side: the environment that carries `payload` to a worker.
--- Parameters go through the environment since `arg` is not populated for the
--- `-c "luafile"` launch (see worker/init.lua).
--- @param payload NtfWorkerPayload
--- @return table<string, string>
function M.env(payload)
  return { [PAYLOAD_ENV] = vim.json.encode(payload) }
end

--- Controller side: extract and decode the result block from a worker's stdout.
--- @param stdout string?
--- @return NtfWorkerResult?
function M.parse(stdout)
  if not stdout then
    return nil
  end
  local from = stdout:find(BEGIN, 1, true)
  local to = stdout:find(END, 1, true)
  if not from or not to then
    return nil
  end
  local json = stdout:sub(from + #BEGIN, to - 1)
  local ok, decoded = pcall(vim.json.decode, json)
  if not ok then
    return nil
  end
  return decoded
end

--- A worker's captured output is everything it wrote to either standard stream.
--- On stdout that means explicit `io.write`/`io.stdout:write`/native writes (the
--- result marker block is excluded; `emit` is always the last thing written). On
--- stderr it means `print`, `vim.api.nvim_echo` and other messages, which Neovim
--- routes to its message channel rather than stdout. The two streams cannot be
--- interleaved after the fact, so stdout is shown first, then stderr.
--- @param stdout string?
--- @param stderr string?
--- @return string
function M.captured_output(stdout, stderr)
  local from = stdout and stdout:find(BEGIN, 1, true)
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
