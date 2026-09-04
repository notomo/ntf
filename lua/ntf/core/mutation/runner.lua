local budget = require("ntf.core.mutation.budget")
local driver = require("ntf.core.worker.driver")
local wait = require("ntf.core.worker.wait")
local verdict = require("ntf.core.mutation.verdict")
local order = require("ntf.core.mutation.order")
local report = require("ntf.core.controller.report")
local relative = require("ntf.core.path").relative

local M = {}

--- @class NtfMutantTrial one test to run against one mutant
--- @field item NtfWorkItem the covering test
--- @field baseline_ms number how long the test took in the baseline run

--- @class NtfMutantTask one mutant and the tests that can detect it
--- @field mutant NtfMutant
--- @field trials NtfMutantTrial[] cheapest first, so a kill is found early
--- @field confirm_kill boolean? take a kill only from a trial that kills twice, for a task that runs every trial it has and so meets a test failing for reasons of its own far more often than one stopping at its first kill

--- @param trial NtfMutantTrial
--- @return NtfWorkerLeaf
local function leaf_of(trial)
  local item = trial.item
  return { file = item.file, node_id = item.node_id, names = item.names, leaves_count = item.leaves_count }
end

-- WHY: a payload reaches its worker through the environment, which every
-- platform caps, so a mutant covered by hundreds of tests has to be taken a
-- batch at a time however many trials are left. Windows caps the whole block at
-- 32767 characters, which is what this is kept well inside of.
-- NOT: one batch over every trial, which spawns nothing at all (E2BIG) for the
-- mutants that have the most trials to save.
--- @type integer characters of leaf data one batch's payload carries at most
local BATCH_CHARS = 16 * 1024

--- @param trial NtfMutantTrial
--- @return integer # what the trial's leaf adds to the encoded payload, near enough to bound it by
local function leaf_chars(trial)
  local item = trial.item
  local chars = #item.file + #item.node_id + 40
  for _, name in ipairs(item.names) do
    chars = chars + #name + 4
  end
  return chars
end

-- WHY: a batch names the test a mutant may have reached; every verdict is still
-- taken from trials run one to a process, so sharing one never becomes evidence
-- of its own -- a kill is confirmed alone, and a mutant no test killed is tried
-- again without a batch.
-- NOT: scoring the batch, where a test failing on what an earlier one left
-- behind reads as a detection, and one passing on it reads as a survival.
--- @param tasks NtfMutantTask[]
--- @param opts { root: string, cwd: string, jobs?: integer, timeout: integer, budget?: integer, test_hook?: string, process_hook?: string, on_task?: fun(outcome: NtfMutantOutcome), on_restart?: fun(trial: NtfMutantTrial) }
--- @return NtfMutantOutcome[] # parallel to tasks
function M.run(tasks, opts)
  local jobs = opts.jobs or vim.uv.available_parallelism()
  local total = #tasks

  local dispatch = order.order(tasks)

  local outcomes = {}
  local started = 0
  local state = { finished = 0, running = {} } --- @type NtfRunState

  local spawn_next
  local run_trial
  local run_batch
  local run_confirm

  --- @type table<integer, true> the tasks a batch was launched for, whose survival is not theirs to report
  local batched = {}

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
  --- @param trial_index integer the trial the worker answers for in the run's reports
  --- @param batch NtfWorkerLeaf[]? the leaves to run in one process, nil to run that trial alone
  --- @param timeout_ms integer ms after which the worker is killed
  --- @param on_outcome fun(outcome: NtfWorkerOutcome)
  local function launch(task_index, trial_index, batch, timeout_ms, on_outcome)
    local task = tasks[task_index]
    state.running[task_index] = report.locator(relative(task.mutant.path, opts.cwd), task.mutant)
    driver.launch(task.trials[trial_index].item, {
      root = opts.root,
      cwd = opts.cwd,
      timeout_override = timeout_ms,
      test_hook = opts.test_hook,
      process_hook = opts.process_hook,
      batch = batch,
      mutation = {
        path = task.mutant.path,
        start_byte = task.mutant.start_byte,
        end_byte = task.mutant.end_byte,
        original = task.mutant.original,
        replacement = task.mutant.replacement,
      },
    }, function(outcome)
      local ok, err = xpcall(function()
        on_outcome(outcome)
      end, debug.traceback)
      if not ok then
        state.fatal = state.fatal or err
        state.finished = state.finished + 1
      end
    end)
  end

  --- @param task_index integer
  --- @param trial_index integer
  --- @param progress NtfMutantProgress what the earlier trials showed
  --- @param confirming boolean? this run repeats a trial that came back killed
  function run_trial(task_index, trial_index, progress, confirming)
    local task = tasks[task_index]
    local trial = task.trials[trial_index]
    if not trial then
      -- WHY: a survival is the one verdict a batch reaches on its own -- a test
      -- that would have failed alone passing on what an earlier one left behind
      -- -- so it is taken again with every trial in a process of its own.
      -- NOT: reporting it, which is a mutant the batch chose not to detect.
      if batched[task_index] then
        batched[task_index] = nil
        return run_trial(task_index, 1, verdict.new_progress())
      end
      return settle(task_index, verdict.exhausted(progress))
    end

    local ceiling = trial.item.timeout or opts.timeout
    launch(task_index, trial_index, nil, budget.trial(trial.baseline_ms, ceiling), function(outcome)
      local settled, next_progress = verdict.step(outcome, progress)
      if settled and settled.status == "killed" and task.confirm_kill and not confirming then
        return run_trial(task_index, trial_index, next_progress, true)
      end
      if settled then
        return settle(task_index, settled)
      end
      run_trial(task_index, trial_index + 1, next_progress)
    end)
  end

  --- @param task_index integer
  --- @param from_index integer the first trial the batch covers
  --- @param progress NtfMutantProgress what the earlier trials showed
  function run_batch(task_index, from_index, progress)
    local task = tasks[task_index]
    -- WHY: a task that re-runs a baseline entry takes every trial it has, so a
    -- batch saves it none, and the survival it ends on is one a batch would
    -- have to hand back to the trials anyway.
    -- NOT: batching it, for a search that has nothing to find early.
    if task.confirm_kill then
      return run_trial(task_index, from_index, progress)
    end

    local trials = task.trials

    local leaves = {}
    local baseline_ms = 0
    local chars = 0
    for index = from_index, #trials do
      chars = chars + leaf_chars(trials[index])
      if #leaves > 0 and chars > BATCH_CHARS then
        break
      end
      table.insert(leaves, leaf_of(trials[index]))
      baseline_ms = baseline_ms + trials[index].baseline_ms
    end

    -- WHY: a batch of one is the trial it holds, run in a process that did
    -- nothing before it, which is what confirming a batched kill produces.
    -- NOT: batching it anyway, which pays a second process for a verdict the
    -- unbatched path already gives.
    if #leaves < 2 then
      return run_trial(task_index, from_index, progress)
    end
    local last_index = from_index + #leaves - 1
    batched[task_index] = true

    launch(task_index, from_index, leaves, budget.trial(baseline_ms, opts.timeout), function(outcome)
      local settled, next_progress = verdict.step(outcome, progress)
      -- WHY: a batch stops at the leaf it failed on, so the trials after that
      -- one are still to be taken, and a batch that failed without the mutated
      -- module ever loading is the run learning nothing rather than the mutant
      -- reaching nothing.
      -- NOT: carrying on past the whole batch, which drops every trial it was
      -- cut short of.
      if not settled then
        local ran_to = outcome.failed_index and from_index + outcome.failed_index - 1 or last_index
        return run_batch(task_index, ran_to + 1, next_progress)
      end
      -- WHY: a batch killed at its own deadline, one whose process died before
      -- it reported, and one failed by a --test-hook teardown rather than by a
      -- leaf all come back naming no leaf, and a verdict no test answers for is
      -- the batch's own length reading as a detection.
      -- NOT: taking it, which is what makes a longer batch detect more than a
      -- shorter one over the same mutant.
      if not outcome.failed_index then
        return run_trial(task_index, from_index, progress)
      end

      -- WHY: the batch's first leaf ran in a process that had done exactly what
      -- a worker given that leaf alone does.
      -- NOT: confirming it, which runs the same process a second time.
      if outcome.failed_index == 1 then
        return settle(task_index, settled)
      end
      run_confirm(task_index, from_index + outcome.failed_index - 1, next_progress)
    end)
  end

  --- @param task_index integer
  --- @param trial_index integer the trial a batch came back killed by
  --- @param progress NtfMutantProgress what the batch showed
  function run_confirm(task_index, trial_index, progress)
    local trial = tasks[task_index].trials[trial_index]
    local ceiling = trial.item.timeout or opts.timeout
    launch(task_index, trial_index, nil, budget.trial(trial.baseline_ms, ceiling), function(outcome)
      local settled, next_progress = verdict.step(outcome, progress)
      if settled then
        return settle(task_index, settled)
      end
      -- WHY: the test the batch was killed by passes alone, so what killed the
      -- batch was a test that ran before it, and the process it left behind is
      -- no place to take the rest of the trials from.
      -- NOT: carrying on in it, which spreads that state over every trial left.
      if opts.on_restart then
        opts.on_restart(trial)
      end
      run_batch(task_index, trial_index + 1, next_progress)
    end)
  end

  spawn_next = function()
    if started >= total then
      return
    end
    started = started + 1
    run_batch(dispatch[started], 1, verdict.new_progress())
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
    error(report.reported_error("the run gave up " .. wait.message(gave_up)), 0)
  end

  return outcomes
end

return M
