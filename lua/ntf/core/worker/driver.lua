local tree = require("ntf.core.tree")
local protocol = require("ntf.core.worker.protocol")
local watchdog = require("ntf.core.worker.watchdog")

local M = {}

--- @type table<integer, table> the workers that have not exited yet, vim.SystemObj by pid
local running = {}

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
--- @field failed_index integer? which of the leaves it was given failed, told from the worker rather than matched back from a name

--- @param item NtfWorkItem
--- @param obj { code: integer, stdout: string?, stderr: string? } vim.system result
--- @param decoded NtfWorkerResult? the block the worker emitted, if it emitted one
--- @param timed_out_ms integer? the timeout the worker was killed for exceeding
--- @return NtfResult[]
local function results_of(item, obj, decoded, timed_out_ms)
  -- WHY: a batch reports leaves of several files, so the file a result answers
  -- for is the one the worker ran it from and stamped it with.
  -- NOT: the item's, which names only the leaf the worker was launched under.
  if decoded and decoded.results and #decoded.results > 0 then
    return decoded.results
  end

  local detail
  if timed_out_ms then
    detail = ("worker timed out after %dms and was killed, so after_each, finally and --test-hook teardown did not run"):format(
      timed_out_ms
    )
  else
    -- WHY: a load_error block is the worker's own report and stderr may hold
    -- unrelated user output (headless print lands there), which the outcome
    -- already carries as captured output.
    -- NOT: preferring stderr, which is the only clue solely when no block was
    -- emitted at all.
    detail = (decoded and decoded.load_error)
      or (obj.stderr ~= "" and obj.stderr)
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

--- @param item NtfWorkItem the leaf the worker answers for in the run's reports; the first of `opts.batch` when it is given one
--- @param opts { cwd: string, timeout: integer?, timeout_override: integer?, test_hook?: string, process_hook?: string, coverage?: boolean, coverage_excludes?: string[], mutation?: NtfWorkerMutation, batch?: NtfWorkerLeaf[] }
--- @return NtfWorkerPayload
--- @return integer? # ms after which the run kills the worker, nil when it is untimed
function M.payload(item, opts)
  local timeout = opts.timeout_override or item.timeout or opts.timeout
  if timeout == 0 then
    timeout = nil
  end

  local watchdog_ms
  if timeout then
    watchdog_ms = watchdog.deadline(timeout)
  end

  return {
    file = item.file,
    node_id = item.node_id,
    names = item.names,
    leaves_count = item.leaves_count,
    batch = opts.batch,
    test_hook = opts.test_hook,
    process_hook = opts.process_hook,
    coverage = opts.coverage or false,
    coverage_excludes = opts.coverage_excludes,
    mutation = opts.mutation,
    cwd = opts.cwd,
    watchdog_ms = watchdog_ms,
    nonce = protocol.nonce(),
  },
    timeout
end

--- @return integer # workers signalled, so a caller can tell a clean finish from a torn-down one
function M.kill_all()
  local killed = 0
  for _, proc in pairs(running) do
    pcall(function()
      proc:kill("sigkill")
    end)
    killed = killed + 1
  end
  running = {}
  return killed
end

--- @param item NtfWorkItem the leaf the worker answers for in the run's reports; the first of `opts.batch` when it is given one
--- @param opts { root: string, cwd: string, timeout: integer?, timeout_override: integer?, test_hook?: string, process_hook?: string, coverage?: boolean, coverage_excludes?: string[], mutation?: NtfWorkerMutation, batch?: NtfWorkerLeaf[] }
--- @param on_done fun(outcome: NtfWorkerOutcome) called from the process-exit callback (a fast event context)
function M.launch(item, opts, on_done)
  local worker = vim.fs.joinpath(opts.root, "lua/ntf/core/worker/init.lua")

  local payload, timeout = M.payload(item, opts)

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
    "--cmd",
    ("lua vim.opt.runtimepath:prepend(%q)"):format(opts.root),
    "-c",
    ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(worker),
  }
  local env = protocol.env(payload)

  -- WHY: a worker spinning in pure Lua never reaches Neovim's event loop to
  -- handle SIGTERM, so only SIGKILL is guaranteed to stop a hung test.
  -- NOT: vim.system's `timeout` option, which sends SIGTERM.
  local timed_out = false
  local timer
  local proc
  proc = vim.system(cmd, { cwd = opts.cwd, env = env, text = true }, function(obj)
    running[proc.pid] = nil
    if timer then
      timer:close()
      timer = nil
    end
    local decoded = protocol.parse(obj.stdout, payload.nonce)
    local outcome = {
      results = results_of(item, obj, decoded, timed_out and timeout or nil),
      coverage = decoded and decoded.coverage or nil,
      timed_out = timed_out or nil,
      mutation_applied = decoded and decoded.mutation_applied,
      failed_index = decoded and decoded.failed_index,
    }
    if decoded then
      local blob = protocol.captured_output(obj.stdout, obj.stderr, payload.nonce)
      if blob ~= "" then
        outcome.output = { file = item.file, name = tree.full_name(item.names), output = blob }
      end
    end
    on_done(outcome)
  end)
  running[proc.pid] = proc
  if timeout then
    timer = assert(vim.uv.new_timer())
    timer:start(timeout, 0, function()
      timed_out = true
      pcall(function()
        proc:kill("sigkill")
      end)
    end)
  end
end

return M
