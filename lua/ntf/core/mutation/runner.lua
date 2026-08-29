local budget = require("ntf.core.mutation.budget")
local driver = require("ntf.core.worker.driver")
local wait = require("ntf.core.worker.wait")
local verdict = require("ntf.core.mutation.verdict")
local order = require("ntf.core.mutation.order")
local locator = require("ntf.core.controller.report").locator
local relative = require("ntf.core.path").relative

local M = {}

--- @class NtfMutantTrial one test to run against one mutant
--- @field item NtfWorkItem the covering test
--- @field baseline_ms number how long the test took in the baseline run

--- @class NtfMutantTask one mutant and the tests that can detect it
--- @field mutant NtfMutant
--- @field trials NtfMutantTrial[] cheapest first, so a kill is found early
--- @field confirm_kill boolean? take a kill only from a trial that kills twice, for a task that runs every trial it has and so meets a test failing for reasons of its own far more often than one stopping at its first kill

-- WHY: each trial runs in its own worker process, exactly as in the baseline
-- run, because ntf has no between-test cleanup.
-- NOT: packing several tests into one process, which would change the hook and
-- global-state semantics and make a mutant look detected for reasons that have
-- nothing to do with it.
--- @param tasks NtfMutantTask[]
--- @param opts { root: string, cwd: string, jobs?: integer, timeout: integer, budget?: integer, test_hook?: string, process_hook?: string, on_task?: fun(outcome: NtfMutantOutcome) }
--- @return NtfMutantOutcome[] # parallel to tasks
function M.run(tasks, opts)
  local jobs = opts.jobs or vim.uv.available_parallelism()
  local total = #tasks

  local dispatch = order.order(tasks)

  local outcomes = {}
  local started = 0
  local state = { finished = 0, running = {} } --- @type NtfRunState

  local spawn_next

  --- @param task_index integer
  --- @param outcome NtfMutantOutcome
  local function settle(task_index, outcome)
    outcomes[task_index] = outcome
    if opts.on_task then
      opts.on_task(outcome)
    end
    state.running[task_index] = nil
    state.finished = state.finished + 1
    vim.schedule(spawn_next)
  end

  --- @param task_index integer
  --- @param trial_index integer
  --- @param progress NtfMutantProgress what the earlier trials showed
  --- @param confirming boolean? this run repeats a trial that came back killed
  local function run_trial(task_index, trial_index, progress, confirming)
    local task = tasks[task_index]
    local trial = task.trials[trial_index]
    if not trial then
      return settle(task_index, verdict.exhausted(progress))
    end

    local ceiling = trial.item.timeout or opts.timeout
    state.running[task_index] = locator(relative(task.mutant.path, opts.cwd), task.mutant)
    driver.launch(trial.item, {
      root = opts.root,
      cwd = opts.cwd,
      timeout_override = budget.trial(trial.baseline_ms, ceiling),
      test_hook = opts.test_hook,
      process_hook = opts.process_hook,
      mutation = {
        path = task.mutant.path,
        start_byte = task.mutant.start_byte,
        end_byte = task.mutant.end_byte,
        original = task.mutant.original,
        replacement = task.mutant.replacement,
      },
    }, function(outcome)
      local ok, err = xpcall(function()
        local settled, next_progress = verdict.step(outcome, progress)
        if settled and settled.status == "killed" and task.confirm_kill and not confirming then
          return run_trial(task_index, trial_index, next_progress, true)
        end
        if settled then
          return settle(task_index, settled)
        end
        run_trial(task_index, trial_index + 1, next_progress)
      end, debug.traceback)
      if not ok then
        state.fatal = state.fatal or err
        state.finished = state.finished + 1
      end
    end)
  end

  spawn_next = function()
    if started >= total then
      return
    end
    started = started + 1
    run_trial(dispatch[started], 1, verdict.new_progress())
  end

  for _ = 1, math.min(jobs, total) do
    spawn_next()
  end

  -- WHY: a score over the mutants that did report back is a percentage of a
  -- denominator the run picked by running out of time, which reads as a
  -- measurement and is not one.
  -- NOT: returning what was scored so far and letting the summary print it, as
  -- the tests do, where every result it prints is one a worker really produced.
  local gave_up = wait.settle(state, { budget = opts.budget, total = total, unit = "mutants" })
  if gave_up then
    error("the run gave up " .. wait.message(gave_up), 0)
  end

  return outcomes
end

return M
