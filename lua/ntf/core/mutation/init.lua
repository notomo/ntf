local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")
local runner = require("ntf.core.mutation.runner")
local baseline = require("ntf.core.mutation.baseline")
local exclude = require("ntf.core.mutation.exclude")
local collector = require("ntf.core.coverage.collector")

local M = {}

--- @class NtfMutant : NtfMutantSite
--- @field path string normalized absolute path of the mutated file

--- @class NtfMutationRecord
--- @field mutant NtfMutant
--- @field status "killed"|"timeout"|"survived"|"no_coverage"|"not_applied"|"equivalent"|"baseline_killable"
--- @field killed_by string? full name of the test that detected the mutant

--- @class NtfMutationSummary
--- @field records NtfMutationRecord[]
--- @field counts table<string, integer> one entry per status, plus `excluded` and `unadopted` for the mutants no record was kept for
--- @field score number? percent detected; nil when nothing was scoreable
--- @field verified integer? baseline entries re-run; nil unless --mutation-verify-baseline=only left the rest unrun
--- @field lost NtfMutationBaselineEntry[] baseline entries that matched no mutant
--- @field unpinned NtfMutationBaselineEntry[] baseline entries whose invariant_spec names no test that passed
--- @field unused_excludes NtfMutationExcludeEntry[] --mutation-config exclude entries covering none of the measurable files
--- @field unused_spec_excludes NtfMutationExcludeEntry[] --mutation-config exclude_spec entries covering none of the discovered spec files

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
--- @param mutation_target string? restrict to this file or directory
--- @param exclude_entries NtfMutationExcludeEntry[] paths left unmutated
--- @return string[] normalized absolute paths, sorted
--- @return NtfMutationExcludeEntry[] # entries covering none of the measurable files
local function target_files(cwd, excludes, mutation_target, exclude_entries)
  local files, unused = exclude.partition(collector.measurable_files(cwd, excludes), exclude_entries, cwd)
  if not mutation_target then
    return files, unused
  end

  local target = normalize(mutation_target)
  return vim.tbl_filter(function(file)
    return file == target or file:sub(1, #target + 1) == target .. "/"
  end, files),
    unused
end

--- @param cwd string normalized absolute working directory
--- @param excludes string[] absolute dir prefixes to skip
--- @param mutation_target string? restrict to this file or directory
--- @param exclude_entries NtfMutationExcludeEntry[] paths left unmutated
--- @param selection NtfMutationOperatorSelection the operators the config adopted
--- @return { mutant: NtfMutant, relative_path: string, line_text: string }[]
--- @return NtfMutationExcludeEntry[] # entries covering none of the measurable files
--- @return integer # mutants an exclude entry named an operator of, left out of the run
--- @return integer # mutants of an operator the config did not adopt, left out of the run
local function enumerate_mutants(cwd, excludes, mutation_target, exclude_entries, selection)
  local entries = {}
  local files, unused = target_files(cwd, excludes, mutation_target, exclude_entries)
  local excluded_operator = exclude.operator_filter(exclude_entries, cwd)
  local adopted = operators.adopted(selection)
  local excluded = 0
  local unadopted = 0
  for _, file in ipairs(files) do
    local src = read_file(file) or ""
    local src_lines = vim.split(src, "\n", { plain = true })
    local relative_path = file:sub(1, #cwd + 1) == cwd .. "/" and file:sub(#cwd + 2) or file
    for _, site in ipairs(operators.enumerate(src)) do
      local mutated = splice.apply(src, site)
      if mutated and loadstring(mutated, "@" .. file) then
        if not adopted(site.operator) then
          unadopted = unadopted + 1
        elseif excluded_operator(file, site.operator) then
          excluded = excluded + 1
        else
          table.insert(entries, {
            mutant = vim.tbl_extend("force", site, { path = file }),
            relative_path = relative_path,
            line_text = src_lines[site.row] or "",
          })
        end
      end
    end
  end
  return entries, unused, excluded, unadopted
end

--- @param mutant NtfMutant
--- @return integer[]
local function rows_of(mutant)
  local rows = {}
  for row = mutant.row, mutant.end_row do
    table.insert(rows, row)
  end
  return vim.list_extend(rows, mutant.anchor_rows)
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
  local scoreable = detected + summary_counts.survived + summary_counts.no_coverage
  if scoreable == 0 then
    return nil
  end
  return 100 * detected / scoreable
end

--- @param ctx { items: NtfWorkItem[], coverage_map: NtfMutationCoverageMap }
--- @param durations table<string, number> baseline test durations, keyed file\0node_id
--- @param mutant NtfMutant
--- @return NtfMutantTrial[] # covering tests, cheapest first, so a kill is found early; empty when uncovered
local function covering_trials(ctx, durations, mutant)
  local trials = vim.tbl_map(function(item_index)
    local item = ctx.items[item_index]
    return { item = item, baseline_ms = durations[item.file .. "\0" .. item.node_id] or 0 }
  end, ctx.coverage_map.item_indexes(mutant.path, rows_of(mutant)))
  table.sort(trials, function(a, b)
    return a.baseline_ms < b.baseline_ms
  end)
  return trials
end

--- @param opts NtfOptions
--- @param ctx { root: string, cwd: string, items: NtfWorkItem[], baseline_results: NtfResult[], baseline: NtfMutationBaselineEntry[]?, mutation_exclude: NtfMutationExcludeEntry[]?, mutation_operators: NtfMutationOperatorSelection?, unused_spec_excludes: NtfMutationExcludeEntry[]?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[], on_start?: fun(total: integer), on_task?: fun(outcome: NtfMutantOutcome) }
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
  --- @type boolean[] whether the task re-runs a baseline entry, parallel to tasks
  local task_verify = {}

  local selection = ctx.mutation_operators or "all"
  local mutant_entries, unused_excludes, excluded, unadopted =
    enumerate_mutants(cwd, ctx.coverage_excludes, opts.mutation_target, ctx.mutation_exclude or {}, selection)
  for _, entry in ipairs(mutant_entries) do
    local mutant = entry.mutant

    if matcher.match(entry.relative_path, entry.line_text, mutant) then
      table.insert(records, { mutant = mutant, status = "equivalent" })

      if opts.mutation_verify_baseline then
        local trials = covering_trials(ctx, durations, mutant)
        if #trials > 0 then
          table.insert(tasks, { mutant = mutant, trials = trials })
          table.insert(task_records, #records)
          table.insert(task_verify, true)
        end
      end
    elseif not opts.mutation_verify_baseline_only then
      table.insert(records, { mutant = mutant, status = "no_coverage" })

      local trials = covering_trials(ctx, durations, mutant)
      if #trials > 0 then
        table.insert(tasks, { mutant = mutant, trials = trials })
        table.insert(task_records, #records)
        table.insert(task_verify, false)
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
    if task_verify[task_index] then
      -- WHY: a trial that ran out of its budget detected nothing, and under load
      -- every trial runs out of it, which would make an equivalence report as
      -- killable on a busy machine and hold on an idle one.
      -- NOT: counting it as detected the way the score does, where reading a
      -- timeout as a kill understates the surviving mutants and here it invents
      -- a failure instead.
      if outcome.status == "killed" then
        record.status = "baseline_killable"
        record.killed_by = outcome.killed_by
      end
    else
      record.status = outcome.status
      record.killed_by = outcome.killed_by
    end
  end

  local counts = {
    killed = 0,
    timeout = 0,
    survived = 0,
    no_coverage = 0,
    not_applied = 0,
    equivalent = 0,
    excluded = excluded,
    unadopted = unadopted,
    baseline_killable = 0,
  }
  for _, record in ipairs(records) do
    counts[record.status] = counts[record.status] + 1
  end

  return {
    records = records,
    counts = counts,
    score = score_of(counts),
    verified = opts.mutation_verify_baseline_only and #tasks or nil,
    lost = matcher.lost(),
    unpinned = baseline.unpinned(ctx.baseline or {}, ctx.baseline_results),
    unused_excludes = unused_excludes,
    unused_spec_excludes = ctx.unused_spec_excludes or {},
  }
end

--- @class NtfMutantListEntry
--- @field mutant NtfMutant
--- @field relative_path string cwd-relative path of the mutated file
--- @field covered_count integer number of tests covering the mutated lines
--- @field equivalent boolean matched by a --mutation-config baseline entry

--- @param opts NtfOptions
--- @param ctx { cwd: string, baseline: NtfMutationBaselineEntry[]?, mutation_exclude: NtfMutationExcludeEntry[]?, mutation_operators: NtfMutationOperatorSelection?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[] }
--- @return NtfMutantListEntry[]
function M.list(opts, ctx)
  local cwd = normalize(ctx.cwd)
  local matcher = baseline.matcher(ctx.baseline or {})

  return vim.tbl_map(
    function(entry)
      local mutant = entry.mutant
      return {
        mutant = mutant,
        relative_path = entry.relative_path,
        covered_count = #ctx.coverage_map.item_indexes(mutant.path, rows_of(mutant)),
        equivalent = matcher.match(entry.relative_path, entry.line_text, mutant),
      }
    end,
    (
      enumerate_mutants(
        cwd,
        ctx.coverage_excludes,
        opts.mutation_target,
        ctx.mutation_exclude or {},
        ctx.mutation_operators or "all"
      )
    )
  )
end

return M
