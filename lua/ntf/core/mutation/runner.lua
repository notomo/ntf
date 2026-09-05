local budget = require("ntf.core.mutation.budget")
local driver = require("ntf.core.worker.driver")
local wait = require("ntf.core.worker.wait")
local order = require("ntf.core.mutation.order")
local tree = require("ntf.core.tree")
local report = require("ntf.core.controller.report")
local relative = require("ntf.core.path").relative

local M = {}

--- @class NtfMutantOutcome
--- @field status "killed"|"timeout"|"survived"|"not_applied"
--- @field killed_by string? full name of the test that detected the mutant

--- @class NtfMutantTrial one test to run against one mutant
--- @field item NtfWorkItem the covering test
--- @field baseline_ms number how long the test took in the baseline run

--- @class NtfMutantTask one mutant and the tests that can detect it
--- @field mutant NtfMutant
--- @field trials NtfMutantTrial[] cheapest first, so a kill is found early

--- @type integer mutants one worker takes before the run starts another for what is left
local CHUNK = 64

--- @param task NtfMutantTask
--- @param index integer the task's place among the run's tasks, which its events name it by
--- @param timeout integer ms the run allows a test that declared no timeout of its own
--- @return NtfWorkerMutantJob
local function job_of(task, index, timeout)
  local trials = vim.tbl_map(function(trial)
    local item = trial.item
    return {
      file = item.file,
      node_id = item.node_id,
      names = item.names,
      leaves_count = item.leaves_count,
      budget_ms = budget.trial(trial.baseline_ms, item.timeout or timeout),
    }
  end, task.trials)

  return {
    index = index,
    mutation = {
      path = task.mutant.path,
      start_byte = task.mutant.start_byte,
      end_byte = task.mutant.end_byte,
      original = task.mutant.original,
      replacement = task.mutant.replacement,
    },
    trials = trials,
  }
end

-- WHY: a mutant is detected by a test that fails on it however many tests ran
-- before it in the process, which is what lets one worker take a chunk of
-- mutants rather than a process take one trial. A test that leaves state behind
-- makes the tests after it answer for the process rather than for the mutant, so
-- a spec of a run is responsible for leaving the editor as it found it.
-- NOT: a process per trial, which is what a normal run gives each test.
--- @param tasks NtfMutantTask[]
--- @param opts { root: string, cwd: string, jobs?: integer, timeout: integer, budget?: integer, test_hook?: string, process_hook?: string, on_task?: fun(outcome: NtfMutantOutcome), on_retry?: fun(name: string) }
--- @return NtfMutantOutcome[] # parallel to tasks
function M.run(tasks, opts)
  local jobs = opts.jobs or vim.uv.available_parallelism()
  local total = #tasks

  local dispatch = order.order(tasks)
  local chunk = math.min(CHUNK, math.max(1, math.ceil(total / jobs)))

  local outcomes = {}
  local dispatched = 0
  local state = { finished = 0, running = {} } --- @type NtfRunState

  --- @param task_index integer
  --- @param outcome NtfMutantOutcome
  local function settle(task_index, outcome)
    outcomes[task_index] = outcome
    if opts.on_task then
      opts.on_task(outcome)
    end
    state.running[task_index] = nil
  end

  local start_worker
  local launch

  --- @param indexes integer[] the tasks one worker is to take, in order
  function launch(indexes)
    local worker_jobs = {}
    for _, task_index in ipairs(indexes) do
      local task = tasks[task_index]
      state.running[task_index] = report.locator(relative(task.mutant.path, opts.cwd), task.mutant)
      table.insert(worker_jobs, job_of(task, task_index, opts.timeout))
    end

    local begun --- @type NtfMutantTrial? the trial the worker last told the run it had started

    --- @generic T
    --- @param fn fun(value: T)
    --- @return fun(value: T) # the same handler, its raise ending the run rather than the worker callback it came from
    local function guarded(fn)
      return function(value)
        if state.closed then
          return
        end
        local ok, err = xpcall(fn, debug.traceback, value)
        if not ok then
          state.fatal = state.fatal or err
        end
      end
    end

    local worker_opts = {
      root = opts.root,
      cwd = opts.cwd,
      test_hook = opts.test_hook,
      process_hook = opts.process_hook,
    }
    driver.launch_mutants(worker_jobs, worker_opts, {
      on_event = guarded(function(event)
        if event.type == "begin" then
          begun = tasks[event.index].trials[event.trial]
          return
        end
        for _, name in ipairs(event.retried or {}) do
          if opts.on_retry then
            opts.on_retry(name)
          end
        end
        settle(event.index, { status = event.status, killed_by = event.killed_by })
      end),
      on_exit = guarded(function(exit)
        local left = {}
        for _, task_index in ipairs(indexes) do
          if not outcomes[task_index] then
            if task_index == exit.pending then
              -- WHY: a worker that died on the trial it had begun took a test
              -- with it, and a test that cannot run to its end on a mutant is
              -- the mutant being noticed rather than the run losing a verdict.
              -- NOT: reading a crash as a survival, which scores a mutant no
              -- test got through as one no test minded.
              local killed_by = begun and tree.full_name(begun.item.names)
              settle(task_index, exit.timed_out and { status = "timeout" } or {
                status = "killed",
                killed_by = killed_by,
              })
            else
              table.insert(left, task_index)
            end
          end
        end

        if #left == #indexes then
          state.fatal = report.reported_error("a mutation worker reported nothing: " .. exit.message)
          return
        end

        -- WHY: a worker writes its verdicts before it exits, so counting them as
        -- they arrive leaves the run over while the process is still there,
        -- holding the working directory a test launched it in open on Windows.
        -- NOT: counting a verdict when it lands, which is when the mutant is
        -- reported and not when the worker that reported it is gone.
        state.finished = state.finished + #indexes - #left

        if #left > 0 then
          return vim.schedule(function()
            launch(left)
          end)
        end
        vim.schedule(start_worker)
      end),
    })
  end

  function start_worker()
    if dispatched >= total then
      return
    end
    local indexes = {}
    while #indexes < chunk and dispatched < total do
      dispatched = dispatched + 1
      table.insert(indexes, dispatch[dispatched])
    end
    launch(indexes)
  end

  for _ = 1, math.min(jobs, total) do
    start_worker()
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
