local driver = require("ntf.core.worker.driver")
local wait = require("ntf.core.worker.wait")
local collector = require("ntf.core.coverage.collector")
local item_locator = require("ntf.core.controller.report").item_locator

local M = {}

--- @class NtfRunTiming
--- @field elapsed number seconds the whole run took
--- @field worker number seconds summed over every worker process that reached its own exit, spawn to exit; jobs of them run at once, so this exceeds elapsed
--- @field killed NtfRunKilled the workers a timeout killed, whose seconds `worker` leaves out
--- @field jobs integer workers run in parallel, whether given or defaulted

--- @class NtfRunKilled
--- @field seconds number seconds summed over the workers a timeout killed
--- @field workers integer how many workers that was, each of which reported exactly one result

--- @param items NtfWorkItem[]
--- @param opts { root: string, jobs?: integer, timeout?: integer, budget?: integer, test_hook?: string, process_hook?: string, coverage?: boolean, coverage_ignore_items?: table<integer, true>, coverage_excludes?: string[], on_item?: fun(item: NtfWorkItem, results: NtfResult[]), on_item_coverage?: fun(item_index: integer, coverage: table?), on_output?: fun(out: NtfWorkerOutput) }
--- @return NtfResult[] results
--- @return table coverage merged per-file line hit counts
--- @return NtfRunTiming timing
--- @return NtfRunGiveUp? # what the run was still waiting on when its budget ran out
function M.run(items, opts)
  local cwd = vim.fn.getcwd()
  local jobs = opts.jobs or vim.uv.available_parallelism()
  local total = #items
  local run_started = vim.uv.hrtime()
  local worker_seconds = 0
  local killed = { seconds = 0, workers = 0 }

  local results = {}
  local merged_coverage = {}
  local coverage_excludes = opts.coverage_excludes
    or collector.exclude_paths(require("ntf.core.controller.discover").default_paths())
  local coverage_ignore_items = opts.coverage_ignore_items or {}
  local started = 0
  local state = { finished = 0, running = {} } --- @type NtfRunState

  local function spawn_next()
    if started >= total then
      return
    end
    started = started + 1
    local item_index = started
    local item = items[item_index]

    local measures_coverage = opts.coverage and not coverage_ignore_items[item_index]

    local item_started = vim.uv.hrtime()
    state.running[item_index] = item_locator(item)
    driver.launch(item, {
      root = opts.root,
      cwd = cwd,
      timeout = opts.timeout,
      test_hook = opts.test_hook,
      process_hook = opts.process_hook,
      coverage = measures_coverage,
      coverage_excludes = coverage_excludes,
    }, function(outcome)
      local seconds = (vim.uv.hrtime() - item_started) * 1e-9
      -- WHY: a killed worker's life measures the timeout the run chose, not the
      -- startup it paid or the test it ran, so the split the report makes of
      -- `worker` has nothing to take from it.
      -- NOT: adding it to `worker`, where the whole timeout lands in the startup
      -- that split leaves over.
      if outcome.timed_out then
        killed.seconds = killed.seconds + seconds
        killed.workers = killed.workers + 1
      else
        worker_seconds = worker_seconds + seconds
      end
      state.running[item_index] = nil
      local ok, err = xpcall(function()
        vim.list_extend(results, outcome.results)
        if measures_coverage then
          collector.merge(merged_coverage, outcome.coverage)
          if opts.on_item_coverage then
            opts.on_item_coverage(item_index, outcome.coverage)
          end
        end
        if opts.on_output and outcome.output then
          opts.on_output(outcome.output)
        end
        if opts.on_item then
          opts.on_item(item, outcome.results)
        end
      end, debug.traceback)
      if not ok then
        state.fatal = state.fatal or err
      end
      state.finished = state.finished + 1
      vim.schedule(spawn_next)
    end)
  end

  for _ = 1, math.min(jobs, total) do
    spawn_next()
  end

  local gave_up = wait.settle(state, { budget = opts.budget, total = total, unit = "tests" })

  if opts.coverage then
    for _, path in ipairs(collector.measurable_files(cwd, coverage_excludes)) do
      if not merged_coverage[path] then
        merged_coverage[path] = { max = 0, lines = {} }
      end
    end
  end

  local timing = {
    elapsed = (vim.uv.hrtime() - run_started) * 1e-9,
    worker = worker_seconds,
    killed = killed,
    jobs = jobs,
  }
  return results, merged_coverage, timing, gave_up
end

return M
