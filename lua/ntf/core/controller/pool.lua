local driver = require("ntf.core.worker.driver")
local collector = require("ntf.core.coverage.collector")

local M = {}

--- Captured output is handed to `on_output` the moment each worker finishes; the
--- cost is that blocks appear in worker-completion order, not deterministic spec order.
--- @param items NtfWorkItem[]
--- @param opts { root: string, jobs?: integer, shuffle?: boolean, seed?: integer, timeout?: integer, test_hook?: string, coverage?: boolean, on_item?: fun(item: NtfWorkItem, results: NtfResult[]), on_output?: fun(out: NtfWorkerOutput) }
--- @return NtfResult[] results, table coverage merged per-file line hit counts
function M.run(items, opts)
  local cwd = vim.fn.getcwd()
  local jobs = opts.jobs or (vim.uv.available_parallelism and vim.uv.available_parallelism()) or 4
  local total = #items

  local results = {}
  local merged_coverage = {}
  local coverage_excludes
  if opts.coverage then
    local spec_files = vim.tbl_map(function(item)
      return item.file
    end, items)
    coverage_excludes = collector.exclude_roots(spec_files, cwd)
  end
  local started = 0
  local finished = 0
  local fatal

  local function spawn_next()
    if started >= total then
      return
    end
    started = started + 1
    local item = items[started]

    driver.launch(item, {
      root = opts.root,
      cwd = cwd,
      timeout = opts.timeout,
      shuffle = opts.shuffle,
      seed = opts.seed,
      test_hook = opts.test_hook,
      coverage = opts.coverage,
      coverage_excludes = coverage_excludes,
    }, function(outcome)
      -- libuv would just log and drop an error raised here; capture the first
      -- to re-raise after the wait.
      local ok, err = xpcall(function()
        vim.list_extend(results, outcome.results)
        if opts.coverage then
          collector.merge(merged_coverage, outcome.coverage)
        end
        if opts.on_output and outcome.output then
          opts.on_output(outcome.output)
        end
        if opts.on_item then
          opts.on_item(item, outcome.results)
        end
      end, debug.traceback)
      if not ok then
        fatal = fatal or err
      end
      finished = finished + 1
      vim.schedule(spawn_next)
    end)
  end

  for _ = 1, math.min(jobs, total) do
    spawn_next()
  end

  vim.wait(10 * 60 * 1000, function()
    return finished >= total or fatal ~= nil
  end, 20)

  if fatal then
    error(fatal, 0)
  end

  if opts.coverage then
    for _, path in ipairs(collector.measurable_files(cwd, coverage_excludes)) do
      if not merged_coverage[path] then
        merged_coverage[path] = { max = 0, lines = {} }
      end
    end
  end

  return results, merged_coverage
end

return M
