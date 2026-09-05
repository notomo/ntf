local tree = require("ntf.core.tree")
local cache_path = require("ntf.core.cache_path")
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

--- @class NtfWorkerMutantsExit what a worker that took mutants came to
--- @field pending integer? the task it had begun and reported no verdict for
--- @field timed_out boolean the run killed it for outlasting the budget of the trial it had begun
--- @field message string what it exited on, for a run that has to say why it reported nothing

--- @param item NtfWorkItem
--- @param obj { code: integer, stdout: string?, stderr: string? } vim.system result
--- @param decoded NtfWorkerResult? the block the worker emitted, if it emitted one
--- @param timed_out_ms integer? the timeout the worker was killed for exceeding
--- @return NtfResult[]
local function results_of(item, obj, decoded, timed_out_ms)
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

--- @param item NtfWorkItem
--- @param opts { cwd: string, timeout: integer?, timeout_override: integer?, test_hook?: string, process_hook?: string, coverage?: boolean, coverage_excludes?: string[], mutation?: NtfWorkerMutation }
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
    leaf = {
      file = item.file,
      node_id = item.node_id,
      names = item.names,
      leaves_count = item.leaves_count,
    },
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
  local signalled = vim.tbl_values(running)
  for _, proc in ipairs(signalled) do
    pcall(function()
      proc:kill("sigkill")
    end)
  end

  -- WHY: Windows keeps a directory open for as long as a process has it as its
  -- working directory, so a signalled worker still holds the one a test launched
  -- it in, which that test's teardown then fails to delete. Waiting is also what
  -- runs each worker's exit callback, which is what takes it off this list.
  -- NOT: returning once they are signalled, which leaves the caller tearing down
  -- around processes that are still there.
  for _, proc in ipairs(signalled) do
    pcall(function()
      proc:wait()
    end)
  end

  return #signalled
end

--- @param root string the plugin root the worker prepends to its runtimepath
--- @return string[] # the command that starts one worker
local function command(root)
  local worker = vim.fs.joinpath(root, "lua/ntf/core/worker/init.lua")
  return {
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
    ("lua vim.opt.runtimepath:prepend(%q)"):format(root),
    "-c",
    ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(worker),
  }
end

--- @param item NtfWorkItem the leaf the worker answers for in the run's reports
--- @param opts { root: string, cwd: string, timeout: integer?, timeout_override: integer?, test_hook?: string, process_hook?: string, coverage?: boolean, coverage_excludes?: string[], mutation?: NtfWorkerMutation }
--- @param on_done fun(outcome: NtfWorkerOutcome) called from the process-exit callback (a fast event context)
function M.launch(item, opts, on_done)
  local payload, timeout = M.payload(item, opts)
  local env = protocol.env(payload)

  -- WHY: a worker spinning in pure Lua never reaches Neovim's event loop to
  -- handle SIGTERM, so only SIGKILL is guaranteed to stop a hung test.
  -- NOT: vim.system's `timeout` option, which sends SIGTERM.
  local timed_out = false
  local timer
  local proc
  proc = vim.system(command(opts.root), { cwd = opts.cwd, env = env, text = true }, function(obj)
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

--- @param jobs NtfWorkerMutantJob[] the mutants one worker takes, in the order it takes them
--- @param opts { root: string, cwd: string, test_hook?: string, process_hook?: string }
--- @param handlers { on_event: fun(event: NtfWorkerEvent), on_exit: fun(exit: NtfWorkerMutantsExit) } both called from a fast event context
function M.launch_mutants(jobs, opts, handlers)
  local nonce = protocol.nonce()
  --- @type NtfWorkerPayload
  local payload = {
    mutants = jobs,
    test_hook = opts.test_hook,
    process_hook = opts.process_hook,
    cwd = opts.cwd,
    nonce = nonce,
  }

  -- WHY: a chunk of mutants names every test that reaches each of them, which is
  -- far past the 32767 characters Windows caps a process environment block at.
  -- NOT: the environment a worker given one leaf is passed through, which spawns
  -- nothing at all (E2BIG) once the chunk is wide enough to be worth taking.
  local env = protocol.env(payload, cache_path.payload(nonce))

  local budgets = {}
  for _, job in ipairs(jobs) do
    budgets[job.index] = vim.tbl_map(function(trial)
      return trial.budget_ms
    end, job.trials)
  end

  local read = protocol.event_reader(nonce)
  local timer = assert(vim.uv.new_timer())
  local pending
  local timed_out = false
  local proc

  local function on_stdout(_, data)
    for _, event in ipairs(read(data)) do
      if event.type == "begin" then
        pending = event.index
        timer:start(budgets[event.index][event.trial], 0, function()
          timed_out = true
          pcall(function()
            proc:kill("sigkill")
          end)
        end)
      else
        pending = nil
      end
      handlers.on_event(event)
    end
  end

  proc = vim.system(command(opts.root), { cwd = opts.cwd, env = env, stdout = on_stdout }, function(obj)
    running[proc.pid] = nil
    timer:close()
    handlers.on_exit({
      pending = pending,
      timed_out = timed_out,
      message = ("worker exited with code %s\n%s"):format(obj.code, obj.stderr or ""),
    })
  end)
  running[proc.pid] = proc
end

return M
