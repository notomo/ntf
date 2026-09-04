local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")
local runner = require("ntf.core.mutation.runner")
local baseline = require("ntf.core.mutation.baseline")
local exclude = require("ntf.core.mutation.exclude")
local collector = require("ntf.core.coverage.collector")
local tree = require("ntf.core.tree")
local absolute = require("ntf.core.path").absolute
local relative = require("ntf.core.path").relative

local M = {}

--- @class NtfMutant : NtfMutantSite
--- @field path string normalized absolute path of the mutated file

--- @class NtfMutationRecord
--- @field mutant NtfMutant
--- @field status "killed"|"timeout"|"survived"|"no_coverage"|"not_applied"|"equivalent"|"baseline_killable"
--- @field killed_by string? full name of the test that detected the mutant

--- @class NtfMutationStaleness what the --config asks for that the code no longer holds, which enumerating the mutants tells without running one
--- @field lost NtfMutationBaselineEntry[] baseline entries that matched no mutant
--- @field ambiguous NtfMutationBaselineAmbiguity[] positions whose content named more than one mutant, with no row to tell them apart
--- @field unpinned NtfMutationBaselineEntry[] baseline entries whose invariant_spec names no test that passed; none where the run took part of the suite, which cannot tell a name that is gone from one it never selected
--- @field uncovered NtfMutationBaselineEntry[] baseline entries no test reaches, carrying no `uncovered` to say so; none where the run took part of the suite, whose coverage is not the suite's
--- @field covered NtfMutationBaselineEntry[] baseline entries carrying `uncovered` that a test does reach, told from any run, since a test that reaches one is reached however few were selected
--- @field unused_excludes NtfMutationExcludeEntry[] --config exclude entries covering none of the measurable files
--- @field unused_spec_excludes NtfMutationExcludeEntry[] --config exclude_spec entries covering none of the discovered spec files, of the ones a spec path of the run holds

--- @class NtfMutationRestart a batched trial whose kill the test did not reproduce when it was run alone, so the batch was what killed it
--- @field mutant NtfMutant
--- @field killed_by string full name of the test the batch came back killed by

--- @class NtfMutationSummary : NtfMutationStaleness
--- @field restarted NtfMutationRestart[] the batches a kill was taken back from, which cost the run the trials they had left
--- @field records NtfMutationRecord[]
--- @field counts table<string, integer> one entry per status, plus `excluded` and `unadopted` for the mutants no record was kept for
--- @field excluded_files integer files a whole-file exclude entry dropped, whose mutants were never enumerated
--- @field score number? percent detected; nil when nothing was scoreable
--- @field verified integer? baseline entries re-run; nil unless `mutation baseline verify` left the rest unrun
--- @field baseline_uncovered integer baseline entries whose `uncovered` the run stood behind, which is what the rest of the entries were not re-run for

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
--- @return integer # files a whole-file exclude entry dropped, of the ones the target holds
local function target_files(cwd, excludes, mutation_target, exclude_entries)
  local files, unused, dropped = exclude.partition(collector.measurable_files(cwd, excludes), exclude_entries, cwd)
  if not mutation_target then
    return files, unused, #dropped
  end

  local target = absolute(mutation_target)
  local within = function(file)
    return file == target or file:sub(1, #target + 1) == target .. "/"
  end
  return vim.tbl_filter(within, files), unused, #vim.tbl_filter(within, dropped)
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
--- @return table<string, true> # the relative paths the run enumerated, which is what a baseline entry is judged against
--- @return integer # files a whole-file exclude entry dropped, whose mutants were never enumerated
local function enumerate_mutants(cwd, excludes, mutation_target, exclude_entries, selection)
  local entries = {}
  local judged = {}
  local files, unused, dropped = target_files(cwd, excludes, mutation_target, exclude_entries)
  local excluded_operator = exclude.operator_filter(exclude_entries, cwd)
  local adopted = operators.adopted(selection)
  local excluded = 0
  local unadopted = 0
  for _, file in ipairs(files) do
    local src = read_file(file) or ""
    local src_lines = vim.split(src, "\n", { plain = true })
    local relative_path = relative(file, cwd)
    judged[relative_path] = true
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
  return entries, unused, excluded, unadopted, judged, dropped
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

--- @param ctx { baseline: NtfMutationBaselineEntry[]?, baseline_results: NtfResult[], whole_suite: boolean, unused_spec_excludes: NtfMutationExcludeEntry[]? }
--- @param matcher NtfMutationBaselineMatcher every mutant of the enumeration has been offered to it
--- @param judged table<string, true> the relative paths the enumeration reached
--- @param unused_excludes NtfMutationExcludeEntry[] exclude entries covering none of the measurable files
--- @param claims NtfMutationBaselineClaims every paired mutant has been recorded with its coverage
--- @return NtfMutationStaleness
local function staleness_of(ctx, matcher, judged, unused_excludes, claims)
  return {
    lost = matcher.lost(judged),
    ambiguous = matcher.ambiguous(),
    unpinned = baseline.unpinned(ctx.baseline or {}, ctx.baseline_results, ctx.whole_suite),
    uncovered = ctx.whole_suite and claims.uncovered() or {},
    covered = claims.covered(),
    unused_excludes = unused_excludes,
    unused_spec_excludes = ctx.unused_spec_excludes or {},
  }
end

--- @param opts NtfOptions
--- @param ctx { root: string, cwd: string, items: NtfWorkItem[], baseline_results: NtfResult[], whole_suite: boolean, baseline: NtfMutationBaselineEntry[]?, mutation_exclude: NtfMutationExcludeEntry[]?, mutation_operators: NtfMutationOperatorSelection?, unused_spec_excludes: NtfMutationExcludeEntry[]?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[], on_start?: fun(total: integer), on_task?: fun(outcome: NtfMutantOutcome) }
--- @return NtfMutationSummary
function M.run(opts, ctx)
  local cwd = absolute(ctx.cwd)
  local durations = baseline_durations(ctx.baseline_results)
  local matcher = baseline.matcher(ctx.baseline or {})
  local claims = baseline.claims()

  --- @type NtfMutationRecord[]
  local records = {}
  --- @type NtfMutantTask[]
  local tasks = {}
  --- @type integer[] index into records, parallel to tasks
  local task_records = {}
  --- @type boolean[] whether the task re-runs a baseline entry, parallel to tasks
  local task_verify = {}

  local selection = ctx.mutation_operators or "all"
  local mutant_entries, unused_excludes, excluded, unadopted, judged, excluded_files =
    enumerate_mutants(cwd, ctx.coverage_excludes, opts.mutation_target, ctx.mutation_exclude or {}, selection)
  for _, entry in ipairs(mutant_entries) do
    local mutant = entry.mutant

    local matched = matcher.match(entry.relative_path, entry.line_text, mutant)
    if matched then
      table.insert(records, { mutant = mutant, status = "equivalent" })

      local trials = covering_trials(ctx, durations, mutant)
      claims.record(matched, #trials > 0)
      if opts.mutation_verify_baseline and #trials > 0 then
        table.insert(tasks, { mutant = mutant, trials = trials, confirm_kill = true })
        table.insert(task_records, #records)
        table.insert(task_verify, true)
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

  --- @type NtfMutationRestart[]
  local restarted = {}
  local outcomes = runner.run(tasks, {
    root = ctx.root,
    cwd = ctx.cwd,
    jobs = opts.jobs,
    timeout = opts.timeout,
    test_hook = opts.test_hook,
    process_hook = opts.process_hook,
    on_task = ctx.on_task,
    on_restart = function(mutant, trial)
      table.insert(restarted, { mutant = mutant, killed_by = tree.full_name(trial.item.names) })
    end,
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

  return vim.tbl_extend("error", staleness_of(ctx, matcher, judged, unused_excludes, claims), {
    restarted = restarted,
    records = records,
    counts = counts,
    excluded_files = excluded_files,
    score = score_of(counts),
    verified = opts.mutation_verify_baseline_only and #tasks or nil,
    baseline_uncovered = claims.acknowledged(),
  })
end

--- @class NtfMutantListEntry
--- @field mutant NtfMutant
--- @field relative_path string cwd-relative path of the mutated file
--- @field covered_count integer number of tests covering the mutated lines
--- @field equivalent boolean matched by a --config baseline entry

--- @param opts NtfOptions
--- @param ctx { cwd: string, baseline: NtfMutationBaselineEntry[]?, baseline_results: NtfResult[], whole_suite: boolean, mutation_exclude: NtfMutationExcludeEntry[]?, mutation_operators: NtfMutationOperatorSelection?, unused_spec_excludes: NtfMutationExcludeEntry[]?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[] }
--- @return NtfMutantListEntry[]
--- @return integer # what the config kept out: excluded or unadopted mutants, and whole files an exclude entry dropped, which is how the listing comes back empty over code that does hold mutants
--- @return NtfMutationStaleness # what the config asks for that the listing found nothing for, told from the same enumeration a run judges it by
function M.list(opts, ctx)
  local cwd = absolute(ctx.cwd)
  local matcher = baseline.matcher(ctx.baseline or {})
  local claims = baseline.claims()

  local entries, unused_excludes, excluded, unadopted, judged, excluded_files = enumerate_mutants(
    cwd,
    ctx.coverage_excludes,
    opts.mutation_target,
    ctx.mutation_exclude or {},
    ctx.mutation_operators or "all"
  )
  local listed = vim.tbl_map(function(entry)
    local mutant = entry.mutant
    local covered_count = #ctx.coverage_map.item_indexes(mutant.path, rows_of(mutant))
    local matched = matcher.match(entry.relative_path, entry.line_text, mutant)
    if matched then
      claims.record(matched, covered_count > 0)
    end
    return {
      mutant = mutant,
      relative_path = entry.relative_path,
      covered_count = covered_count,
      equivalent = matched,
    }
  end, entries)
  return listed, excluded + unadopted + excluded_files, staleness_of(ctx, matcher, judged, unused_excludes, claims)
end

return M
