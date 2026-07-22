local driver = require("ntf.core.worker.driver")
local tree = require("ntf.core.tree")
local order = require("ntf.core.mutation.order")

local M = {}

--- @class NtfMutantTrial one test to run against one mutant
--- @field item NtfWorkItem the covering test
--- @field baseline_ms number how long the test took in the baseline run

--- @class NtfMutantTask one mutant and the tests that can detect it
--- @field mutant NtfMutant
--- @field trials NtfMutantTrial[] cheapest first, so a kill is found early

--- @class NtfMutantOutcome
--- @field status "killed"|"timeout"|"survived"|"not_applied"
--- @field killed_by string? full name of the first test that detected the mutant

-- WHY: a mutant that turns a loop infinite must not burn a full timeout per
-- trial, so a trial gets a budget scaled to what the test cost in the baseline.
-- NOT: the run's own per-test timeout.
--- @param baseline_ms number
--- @param timeout integer the run's per-test timeout in ms (0 disables)
--- @return integer
local function trial_timeout(baseline_ms, timeout)
  local budget = math.max(3000, 2 * baseline_ms + 2000)
  if timeout > 0 then
    budget = math.min(budget, timeout)
  end
  return math.floor(budget)
end

--- @param outcome NtfWorkerOutcome
--- @return NtfMutantOutcome? # nil when this trial did not settle the mutant
local function classify(outcome)
  if outcome.timed_out then
    return { status = "timeout" }
  end
  for _, result in ipairs(outcome.results) do
    if result.status == "failed" or result.status == "error" then
      return { status = "killed", killed_by = tree.full_name(result.names or {}) }
    end
  end
  -- WHY: a crashed worker reports nothing at all, and its results have already
  -- been read as a kill above, so only an explicit `false` means not applied.
  -- NOT: treating an absent report as not applied.
  if outcome.mutation_applied == false then
    return { status = "not_applied" }
  end
  return nil
end

-- WHY: each trial runs in its own worker process, exactly as in the baseline
-- run, because ntf has no between-test cleanup.
-- NOT: packing several tests into one process, which would change the hook and
-- global-state semantics and make a mutant look detected for reasons that have
-- nothing to do with it.
--- @param tasks NtfMutantTask[]
--- @param opts { root: string, cwd: string, jobs?: integer, timeout: integer, test_hook?: string, on_task?: fun(outcome: NtfMutantOutcome) }
--- @return NtfMutantOutcome[] # parallel to tasks
function M.run(tasks, opts)
  local jobs = opts.jobs or (vim.uv.available_parallelism and vim.uv.available_parallelism()) or 4
  local total = #tasks

  local dispatch = order.order(tasks)

  local outcomes = {}
  local started = 0
  local finished = 0
  local fatal

  local spawn_next

  --- @param task_index integer
  --- @param outcome NtfMutantOutcome
  local function settle(task_index, outcome)
    outcomes[task_index] = outcome
    if opts.on_task then
      opts.on_task(outcome)
    end
    finished = finished + 1
    vim.schedule(spawn_next)
  end

  --- @param task_index integer
  --- @param trial_index integer
  local function run_trial(task_index, trial_index)
    local task = tasks[task_index]
    local trial = task.trials[trial_index]
    if not trial then
      return settle(task_index, { status = "survived" })
    end

    driver.launch(trial.item, {
      root = opts.root,
      cwd = opts.cwd,
      timeout = trial_timeout(trial.baseline_ms, opts.timeout),
      test_hook = opts.test_hook,
      mutation = {
        path = task.mutant.path,
        start_byte = task.mutant.start_byte,
        end_byte = task.mutant.end_byte,
        original = task.mutant.original,
        replacement = task.mutant.replacement,
      },
    }, function(outcome)
      -- WHY: libuv would just log and drop an error raised here, so the first
      -- one is captured and re-raised after the wait.
      -- NOT: running the body bare and letting it throw into the libuv callback.
      local ok, err = xpcall(function()
        local settled = classify(outcome)
        if settled then
          return settle(task_index, settled)
        end
        run_trial(task_index, trial_index + 1)
      end, debug.traceback)
      if not ok then
        fatal = fatal or err
        finished = finished + 1
      end
    end)
  end

  spawn_next = function()
    if started >= total then
      return
    end
    started = started + 1
    run_trial(dispatch[started], 1)
  end

  for _ = 1, math.min(jobs, total) do
    spawn_next()
  end

  local budget = math.max(10 * 60 * 1000, total * 10 * 1000)
  vim.wait(budget, function()
    return finished >= total or fatal ~= nil
  end, 20)

  if fatal then
    error(fatal, 0)
  end

  return outcomes
end

return M
