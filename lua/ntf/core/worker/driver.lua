-- The controller-side view of one worker: launch the process for a work item
-- and interpret whatever comes back (results, coverage, captured output).
local tree = require("ntf.core.tree")
local protocol = require("ntf.core.worker.protocol")

local M = {}

--- @class NtfWorkerOutput
--- @field file string spec file path
--- @field name string the test the worker covered (its full describe/it name)
--- @field output string captured stdout/stderr blob

--- @class NtfWorkerOutcome
--- @field results NtfResult[]
--- @field coverage table? per-file line hit counts (when coverage was measured)
--- @field output NtfWorkerOutput? captured user output, when there was any

--- @param item NtfWorkItem
--- @param obj { code: integer, stdout: string?, stderr: string? } vim.system result
--- @param timed_out_ms integer? the timeout the worker was killed for exceeding
--- @return NtfResult[]
local function results_of(item, obj, timed_out_ms)
  local decoded = protocol.parse(obj.stdout)

  if decoded and decoded.results then
    for _, result in ipairs(decoded.results) do
      result.file = item.file
    end
    return decoded.results
  end

  local detail
  if timed_out_ms then
    detail = ("worker timed out after %dms"):format(timed_out_ms)
  else
    detail = (obj.stderr ~= "" and obj.stderr)
      or (decoded and decoded.load_error)
      or ("worker exited with code " .. tostring(obj.code))
  end
  return {
    {
      file = item.file,
      id = item.node_id,
      names = item.names,
      trace = item.trace,
      status = "error",
      message = detail,
    },
  }
end

--- @param item NtfWorkItem
--- @param opts { root: string, cwd: string, timeout: integer?, shuffle?: boolean, seed?: integer, test_hook?: string, coverage?: boolean, coverage_excludes?: string[] }
--- @param on_done fun(outcome: NtfWorkerOutcome) called from the process-exit callback (a fast event context)
function M.launch(item, opts, on_done)
  local worker = vim.fs.joinpath(opts.root, "lua/ntf/core/worker/init.lua")

  local timeout = item.timeout or opts.timeout
  if timeout == 0 then
    timeout = nil
  end

  -- Launch via `-c "luafile"` (after startup) instead of `-l`: see worker/init.lua.
  local cmd = {
    vim.v.progpath,
    "--clean",
    "--headless",
    -- Workers run in parallel in the same cwd, where the swap file name for an
    -- unnamed buffer is shared, so concurrent workers collide on it (E303).
    -- Tests do not need swap files; disable before the first buffer is created.
    "--cmd",
    "set noswapfile",
    -- The worker script cannot require any ntf module until the ntf root is on
    -- runtimepath, so that happens at startup, before `-c` runs the script.
    "--cmd",
    ("lua vim.opt.runtimepath:prepend(%q)"):format(opts.root),
    "-c",
    ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(worker),
  }
  local env = protocol.env({
    file = item.file,
    node_id = item.node_id,
    shuffle = opts.shuffle or false,
    seed = opts.seed,
    test_hook = opts.test_hook,
    coverage = opts.coverage or false,
    coverage_excludes = opts.coverage_excludes,
    cwd = opts.cwd,
  })

  -- We enforce the timeout ourselves with SIGKILL rather than vim.system's
  -- `timeout` option, which sends SIGTERM. A worker spinning in pure Lua never
  -- reaches Neovim's event loop to handle SIGTERM, so only SIGKILL is guaranteed
  -- to stop a hung test.
  local timed_out = false
  local timer
  local proc = vim.system(cmd, { cwd = opts.cwd, env = env, text = true }, function(obj)
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    local decoded = protocol.parse(obj.stdout)
    local outcome = {
      results = results_of(item, obj, timed_out and timeout or nil),
      coverage = decoded and decoded.coverage or nil,
    }
    if decoded then
      local blob = protocol.captured_output(obj.stdout, obj.stderr)
      if blob ~= "" then
        outcome.output = { file = item.file, name = tree.full_name(item.names), output = blob }
      end
    end
    on_done(outcome)
  end)
  if timeout then
    timer = vim.uv.new_timer()
    if timer then
      timer:start(timeout, 0, function()
        timed_out = true
        pcall(function()
          proc:kill(9)
        end)
      end)
    end
  end
end

return M
