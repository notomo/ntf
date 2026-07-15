local operators = require("ntf.core.mutation.operators")
local runner = require("ntf.core.mutation.runner")
local baseline = require("ntf.core.mutation.baseline")
local collector = require("ntf.core.coverage.collector")

local M = {}

--- @class NtfMutant : NtfMutantSite
--- @field path string normalized absolute path of the mutated file

--- @class NtfMutationRecord
--- @field mutant NtfMutant
--- @field status "killed"|"timeout"|"survived"|"no_coverage"|"not_applied"|"equivalent"
--- @field killed_by string? full name of the test that detected the mutant

--- @class NtfMutationSummary
--- @field records NtfMutationRecord[]
--- @field counts table<string, integer> one entry per status
--- @field score number? percent detected; nil when nothing was scoreable
--- @field lost NtfMutationBaselineEntry[] baseline entries that matched no mutant

--- @param path string any form of a path
--- @return string
local function normalize(path)
  return (vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", ""))
end

--- @param file string absolute path
--- @return string?
local function read_file(file)
  local f = io.open(file, "r")
  if not f then
    return nil
  end
  local src = f:read("*a")
  f:close()
  return src
end

--- @param cwd string normalized absolute working directory
--- @param excludes string[] absolute dir prefixes to skip
--- @param mutation_path string? restrict to this file or directory
--- @return string[] normalized absolute paths, sorted
local function target_files(cwd, excludes, mutation_path)
  local files = collector.measurable_files(cwd, excludes)
  if not mutation_path then
    return files
  end

  local target = normalize(mutation_path)
  return vim.tbl_filter(function(file)
    return file == target or file:sub(1, #target + 1) == target .. "/"
  end, files)
end

--- @param results NtfResult[]
--- @return table<string, number> # "<file>\0<id>" -> duration in ms
local function baseline_durations(results)
  local durations = {}
  for _, result in ipairs(results) do
    if result.file then
      durations[result.file .. "\0" .. result.id] = (result.duration or 0) * 1000
    end
  end
  return durations
end

--- @param summary_counts table<string, integer>
--- @return number?
local function score_of(summary_counts)
  local detected = summary_counts.killed + summary_counts.timeout
  -- A mutant no test reaches is undetected, not excluded: that is exactly what a
  -- coverage hole costs. A mutant that was never actually loaded, on the other
  -- hand, says nothing about the tests, so it stays out of the score.
  -- A baseline-equivalent mutant is undetectable by definition, so it also
  -- stays out.
  local scoreable = detected + summary_counts.survived + summary_counts.no_coverage
  if scoreable == 0 then
    return nil
  end
  return 100 * detected / scoreable
end

--- @param opts NtfOptions
--- @param ctx { root: string, cwd: string, items: NtfWorkItem[], baseline_results: NtfResult[], baseline: NtfMutationBaselineEntry[]?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[], on_start?: fun(total: integer), on_task?: fun(outcome: NtfMutantOutcome) }
--- @return NtfMutationSummary
function M.run(opts, ctx)
  local cwd = normalize(ctx.cwd)
  local durations = baseline_durations(ctx.baseline_results)
  local matcher = baseline.matcher(ctx.baseline or {})

  --- @type NtfMutationRecord[]
  local records = {}
  --- @type NtfMutantTask[]
  local tasks = {}
  --- @type integer[] index into records, parallel to tasks
  local task_records = {}

  for _, file in ipairs(target_files(cwd, ctx.coverage_excludes, opts.mutation_path)) do
    local src = read_file(file) or ""
    local src_lines = vim.split(src, "\n", { plain = true })
    local relative_path = file:sub(1, #cwd + 1) == cwd .. "/" and file:sub(#cwd + 2) or file
    for _, site in ipairs(operators.enumerate(src)) do
      -- A mutant that does not compile would make every covering test error out
      -- and so count as detected, inflating the score. The operators are meant to
      -- keep the source valid; this only guards against a grammar surprise.
      local mutated = operators.apply(src, site)
      if mutated and loadstring(mutated, "@" .. file) then
        --- @type NtfMutant
        local mutant = vim.tbl_extend("force", site, { path = file })

        if matcher.match(relative_path, src_lines[site.row] or "", site) then
          table.insert(records, { mutant = mutant, status = "equivalent" })
        else
          local rows = {}
          for row = mutant.row, mutant.end_row do
            table.insert(rows, row)
          end

          table.insert(records, { mutant = mutant, status = "no_coverage" })

          local item_indexes = ctx.coverage_map.item_indexes(file, rows)
          if #item_indexes > 0 then
            local trials = vim.tbl_map(function(item_index)
              local item = ctx.items[item_index]
              return { item = item, baseline_ms = durations[item.file .. "\0" .. item.node_id] or 0 }
            end, item_indexes)
            table.sort(trials, function(a, b)
              return a.baseline_ms < b.baseline_ms
            end)

            table.insert(tasks, { mutant = mutant, trials = trials })
            table.insert(task_records, #records)
          end
        end
      end
    end
  end

  if ctx.on_start then
    ctx.on_start(#tasks)
  end

  local outcomes = runner.run(tasks, {
    root = ctx.root,
    cwd = ctx.cwd,
    jobs = opts.jobs,
    timeout = opts.timeout,
    test_hook = opts.test_hook,
    on_task = ctx.on_task,
  })
  for task_index, outcome in pairs(outcomes) do
    local record = records[task_records[task_index]]
    record.status = outcome.status
    record.killed_by = outcome.killed_by
  end

  local counts = { killed = 0, timeout = 0, survived = 0, no_coverage = 0, not_applied = 0, equivalent = 0 }
  for _, record in ipairs(records) do
    counts[record.status] = counts[record.status] + 1
  end

  return { records = records, counts = counts, score = score_of(counts), lost = matcher.lost() }
end

return M
