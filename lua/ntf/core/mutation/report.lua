local controller_report = require("ntf.core.controller.report")
local painter = controller_report.painter
local duration = controller_report.duration
local oneline = controller_report.oneline
local locator = controller_report.locator
local absolute = require("ntf.core.path").absolute

local M = {}

--- @type table<string, { label: string, color: string }> the statuses a record gets a line of its own under
M.listed = {
  timeout = { label = "TIMEOUT", color = "yellow" },
  survived = { label = "SURVIVED", color = "red" },
  no_coverage = { label = "NO COVERAGE", color = "yellow" },
  not_applied = { label = "NOT APPLIED", color = "yellow" },
  baseline_killable = { label = "BASELINE KILLABLE", color = "red" },
}

--- @type table<string, string> the lines a config entry the run cannot stand behind is reported under
M.entry_labels = {
  unused_exclude = "UNUSED EXCLUDE",
  unused_exclude_spec = "UNUSED EXCLUDE SPEC",
  unpinned = "UNPINNED BASELINE",
  lost = "LOST BASELINE",
  ambiguous = "AMBIGUOUS BASELINE",
}

--- @type { status: string, label: string, color: string }[] the statuses the count line tallies, in its order
M.count_labels = {
  { status = "killed", label = "killed", color = "green" },
  { status = "timeout", label = "timeout", color = "green" },
  { status = "survived", label = "survived", color = "red" },
  { status = "no_coverage", label = "no coverage", color = "yellow" },
  { status = "not_applied", label = "not applied", color = "yellow" },
  { status = "equivalent", label = "equivalent", color = "green" },
  { status = "excluded", label = "excluded", color = "green" },
  { status = "unadopted", label = "unadopted", color = "green" },
  { status = "baseline_killable", label = "baseline killable", color = "red" },
}

--- @param file string absolute path
--- @param cwd string? normalized absolute working directory
--- @return string
local function relative(file, cwd)
  if cwd and file:sub(1, #cwd + 1) == cwd .. "/" then
    return file:sub(#cwd + 2)
  end
  return file
end

--- @param summary NtfMutationSummary
--- @param cwd string? working directory, to show file paths relative to it
--- @param opts { color: boolean, elapsed: number } seconds the scoring pass took, which the tests it was run from are timed apart from
--- @return string
function M.summary(summary, cwd, opts)
  cwd = cwd and absolute(cwd) or nil
  local paint = painter(opts.color)
  local counts = summary.counts

  local lines = {}
  if summary.verified then
    table.insert(
      lines,
      ("Baseline: %d/%d entries re-run"):format(summary.verified, counts.equivalent + counts.baseline_killable)
    )
  else
    if summary.score then
      local detected = counts.killed + counts.timeout
      local scoreable = detected + counts.survived + counts.no_coverage
      table.insert(lines, ("Mutation: %.1f%% (%d/%d mutants detected)"):format(summary.score, detected, scoreable))
    elseif #summary.records == 0 then
      table.insert(lines, "Mutation: n/a (no mutants)")
    else
      table.insert(lines, "Mutation: n/a (no mutant scored)")
    end

    local parts = {}
    for _, entry in ipairs(M.count_labels) do
      local count = counts[entry.status]
      if count > 0 then
        table.insert(parts, paint(entry.color, ("%d %s"):format(count, entry.label)))
      end
    end
    if #parts > 0 then
      table.insert(lines, "  " .. table.concat(parts, "  "))
    end
  end
  lines[1] = lines[1] .. ", " .. duration(opts.elapsed) .. " elapsed"

  for _, record in ipairs(summary.records) do
    local listed = M.listed[record.status]
    if listed then
      local mutant = record.mutant
      local killer = ""
      if record.killed_by then
        killer = (" killed by %q"):format(record.killed_by)
      end
      table.insert(
        lines,
        ("%s %s %s -> %s%s"):format(
          paint(listed.color, listed.label),
          locator(relative(mutant.path, cwd), mutant),
          oneline(mutant.original),
          oneline(mutant.replacement),
          killer
        )
      )
    end
  end

  for _, entry in ipairs(summary.unused_excludes or {}) do
    table.insert(lines, ("%s %s"):format(paint("red", M.entry_labels.unused_exclude), entry.path))
  end

  for _, entry in ipairs(summary.unused_spec_excludes or {}) do
    table.insert(lines, ("%s %s"):format(paint("red", M.entry_labels.unused_exclude_spec), entry.path))
  end

  for _, entry in ipairs(summary.unpinned or {}) do
    table.insert(
      lines,
      ("%s %s %s: %s -> %s wants a passing %q"):format(
        paint("red", M.entry_labels.unpinned),
        entry.path,
        entry.operator,
        oneline(entry.original),
        oneline(entry.replacement),
        entry.invariant_spec
      )
    )
  end

  for _, ambiguity in ipairs(summary.ambiguous or {}) do
    local entry = ambiguity.entry
    table.insert(
      lines,
      ("%s %s %s: %s -> %s names rows %s; give each entry its row"):format(
        paint("red", M.entry_labels.ambiguous),
        entry.path,
        entry.operator,
        oneline(entry.original),
        oneline(entry.replacement),
        table.concat(vim.tbl_map(tostring, ambiguity.rows), ", ")
      )
    )
  end

  for _, entry in ipairs(summary.lost or {}) do
    table.insert(
      lines,
      ("%s %s %s: %s -> %s at %q"):format(
        paint("red", M.entry_labels.lost),
        entry.path,
        entry.operator,
        oneline(entry.original),
        oneline(entry.replacement),
        entry.line
      )
    )
  end

  return table.concat(lines, "\n") .. "\n"
end

return M
