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
--- @field timed_out boolean? the worker was killed for exceeding its timeout
--- @field mutation_applied boolean? the mutated module was loaded (mutation runs only)

--- @param item NtfWorkItem
--- @param obj { code: integer, stdout: string?, stderr: string? } vim.system result
--- @param timed_out_ms integer? the timeout the worker was killed for exceeding
--- @return NtfResult[]
local function results_of(item, obj, timed_out_ms)
  local decoded = protocol.parse(obj.stdout)

  -- WHY: the worker runs exactly one requested node, so reporting nothing means
  -- the node was never found in the rebuilt tree (a mutant broke the id scheme,
  -- say).
  -- NOT: reading an empty result list as a clean pass.
  if decoded and decoded.results and #decoded.results > 0 then
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
      or (decoded and decoded.results and "worker reported no result for the requested test")
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
--- @param opts { root: string, cwd: string, timeout: integer?, test_hook?: string, coverage?: boolean, coverage_excludes?: string[], mutation?: NtfWorkerMutation }
--- @param on_done fun(outcome: NtfWorkerOutcome) called from the process-exit callback (a fast event context)
function M.launch(item, opts, on_done)
  local worker = vim.fs.joinpath(opts.root, "lua/ntf/core/worker/init.lua")

  local timeout = item.timeout or opts.timeout
  if timeout == 0 then
    timeout = nil
  end

  -- WHY: the worker script is launched by `-c "luafile"`, after startup, for
  -- the reason worker/init.lua gives.
  -- NOT: `-l`.
  local cmd = {
    vim.v.progpath,
    "--clean",
    "--headless",
    -- WHY: workers run in parallel in the same cwd, where the swap file name for
    -- an unnamed buffer is shared, so concurrent workers collide on it (E303).
    -- `--cmd` lands before the first buffer is created.
    -- NOT: setting it from the worker script, which runs after that buffer
    -- exists.
    "--cmd",
    "set noswapfile",
    -- WHY: the worker script cannot require any ntf module until the ntf root is
    -- on runtimepath.
    -- NOT: prepending it from the worker script itself, which is already an ntf
    -- module.
    "--cmd",
    ("lua vim.opt.runtimepath:prepend(%q)"):format(opts.root),
    "-c",
    ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(worker),
  }
  local env = protocol.env({
    file = item.file,
    node_id = item.node_id,
    test_hook = opts.test_hook,
    coverage = opts.coverage or false,
    coverage_excludes = opts.coverage_excludes,
    mutation = opts.mutation,
    cwd = opts.cwd,
  })

  -- WHY: a worker spinning in pure Lua never reaches Neovim's event loop to
  -- handle SIGTERM, so only SIGKILL is guaranteed to stop a hung test.
  -- NOT: vim.system's `timeout` option, which sends SIGTERM.
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
      timed_out = timed_out or nil,
      -- WHY: a worker that never loaded the mutated module reports `false`, and
      -- the controller must be able to tell that from "no report".
      -- NOT: `or nil`, which would collapse the two.
      mutation_applied = decoded and decoded.mutation_applied,
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
