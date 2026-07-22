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

-- WHY: `M.parse` splits a worker's stdout at the first marker pair and the
-- controller keeps what comes before it as the test's own output, so this must
-- be the last stdout write of the worker.
-- NOT: emitting a partial result early and a final one later; the second block
-- would land inside the first one's span.
--- @param result NtfWorkerResult
function M.emit(result)
  io.stdout:write("\n" .. BEGIN .. "\n")
  io.stdout:write(vim.json.encode(result))
  io.stdout:write("\n" .. END .. "\n")
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
--- @return NtfWorkerResult? the decoded result block, if the stdout carries one
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

-- WHY: stderr counts as the worker's own output too, since Neovim routes
-- `print`, `vim.api.nvim_echo` and other messages to its message channel rather
-- than to stdout.
-- NOT: interleaving the two in write order, which is unrecoverable once both
-- streams have been collected, so stdout is shown whole and then stderr.
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
