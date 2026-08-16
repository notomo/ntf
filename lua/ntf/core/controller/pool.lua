local driver = require("ntf.core.worker.driver")
local wait = require("ntf.core.worker.wait")
local collector = require("ntf.core.coverage.collector")

local M = {}

--- @class NtfRunTiming
--- @field elapsed number seconds the whole run took
--- @field worker number seconds summed over every worker process, spawn to exit; jobs of them run at once, so this exceeds elapsed
--- @field jobs integer workers run in parallel, whether given or defaulted

--- @param items NtfWorkItem[]
--- @param opts { root: string, jobs?: integer, timeout?: integer, test_hook?: string, coverage?: boolean, coverage_excludes?: string[], on_item?: fun(item: NtfWorkItem, results: NtfResult[]), on_item_coverage?: fun(item_index: integer, coverage: table?), on_output?: fun(out: NtfWorkerOutput) }
--- @return NtfResult[] results
--- @return table coverage merged per-file line hit counts
--- @return NtfRunTiming timing
function M.run(items, opts)
  local cwd = vim.fn.getcwd()
  local jobs = opts.jobs or vim.uv.available_parallelism()
  local total = #items
  local run_started = vim.uv.hrtime()
  local worker_seconds = 0

  local results = {}
  local merged_coverage = {}
  local spec_files = vim.tbl_map(function(item)
    return item.file
  end, items)
  local coverage_excludes = opts.coverage_excludes or collector.exclude_roots(spec_files, cwd)
  local started = 0
  local state = { finished = 0 } --- @type NtfRunState

  local function spawn_next()
    if started >= total then
      return
    end
    started = started + 1
    local item_index = started
    local item = items[item_index]

    local item_started = vim.uv.hrtime()
    driver.launch(item, {
      root = opts.root,
      cwd = cwd,
      timeout = opts.timeout,
      test_hook = opts.test_hook,
      coverage = opts.coverage,
      coverage_excludes = coverage_excludes,
    }, function(outcome)
      worker_seconds = worker_seconds + (vim.uv.hrtime() - item_started) * 1e-9
      local ok, err = xpcall(function()
        vim.list_extend(results, outcome.results)
        if opts.coverage then
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

  wait.settle(state, { budget = 10 * 60 * 1000, total = total, unit = "tests" })

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
    jobs = jobs,
  }
  return results, merged_coverage, timing
end

return M
