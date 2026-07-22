local painter = require("ntf.core.controller.report").painter

local M = {}

-- WHY: an undetected mutant is the one that says something about the tests; a
-- detected one only moves the score.
-- NOT: a line per mutant for every status in `COUNT_LABELS`.
local LISTED = {
  survived = { label = "SURVIVED", color = "red" },
  no_coverage = { label = "NO COVERAGE", color = "yellow" },
  not_applied = { label = "NOT APPLIED", color = "yellow" },
}

local COUNT_LABELS = {
  { status = "killed", label = "killed", color = "green" },
  { status = "timeout", label = "timeout", color = "green" },
  { status = "survived", label = "survived", color = "red" },
  { status = "no_coverage", label = "no coverage", color = "yellow" },
  { status = "not_applied", label = "not applied", color = "yellow" },
  { status = "equivalent", label = "equivalent", color = "green" },
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
--- @param opts { color: boolean }
--- @return string
function M.summary(summary, cwd, opts)
  cwd = cwd and (vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p")):gsub("/$", "")) or nil
  local paint = painter(opts.color)
  local counts = summary.counts

  local lines = {}
  if not summary.score then
    table.insert(lines, "Mutation: n/a (no mutants)")
  else
    local detected = counts.killed + counts.timeout
    local scoreable = detected + counts.survived + counts.no_coverage
    table.insert(lines, ("Mutation: %.1f%% (%d/%d mutants detected)"):format(summary.score, detected, scoreable))

    local parts = {}
    for _, entry in ipairs(COUNT_LABELS) do
      local count = counts[entry.status]
      if count > 0 then
        table.insert(parts, paint(entry.color, ("%d %s"):format(count, entry.label)))
      end
    end
    table.insert(lines, "  " .. table.concat(parts, "  "))
  end

  for _, record in ipairs(summary.records) do
    local listed = LISTED[record.status]
    if listed then
      local mutant = record.mutant
      table.insert(
        lines,
        ("%s %s:%d %s: %s -> %s"):format(
          paint(listed.color, listed.label),
          relative(mutant.path, cwd),
          mutant.row,
          mutant.operator,
          mutant.original,
          mutant.replacement
        )
      )
    end
  end

  for _, entry in ipairs(summary.lost or {}) do
    table.insert(
      lines,
      ("%s %s %s: %s -> %s at %q"):format(
        paint("red", "LOST BASELINE"),
        entry.path,
        entry.operator,
        entry.original,
        entry.replacement,
        entry.line
      )
    )
  end

  return table.concat(lines, "\n") .. "\n"
end

return M
