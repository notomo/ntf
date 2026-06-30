-- A small built-in coverage summary printed after a run. It is deliberately
-- "simple": the denominator (coverable lines) comes from a treesitter analysis
-- of the source, so the percentages are approximate. For authoritative, per-line
-- reports point LuaCov at the emitted `luacov.stats.out`.
local coverable_lines = require("ntf.core.coverage.source").coverable_lines

local M = {}

--- @param file string absolute path
--- @return string[]|nil
local function read_lines(file)
  local f = io.open(file, "r")
  if not f then
    return nil
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()
  return lines
end

--- Coverable/covered line counts for one file from its source and hit counts.
--- @param source_lines string[]
--- @param hits table<integer, integer>
--- @return integer covered, integer coverable
local function count_file(source_lines, hits)
  local coverable, covered = 0, 0
  -- Union the source's coverable lines with every line that was actually hit, so
  -- a recorded line is never dropped from the denominator.
  local seen = {}
  for line in pairs(hits) do
    seen[line] = true
  end
  for line in pairs(coverable_lines(table.concat(source_lines, "\n"))) do
    seen[line] = true
  end
  for line in pairs(seen) do
    coverable = coverable + 1
    if (hits[line] or 0) > 0 then
      covered = covered + 1
    end
  end
  return covered, coverable
end

--- @param merged table<string, { max: integer, lines: table<integer, integer> }>
--- @param cwd string? working directory, to show file paths relative to it
--- @return string
function M.summary(merged, cwd)
  cwd = cwd and (vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p")):gsub("/$", "")) or nil

  local files = vim.tbl_keys(merged)
  table.sort(files)

  local rows = {}
  local total_covered, total_coverable = 0, 0
  local width = 0
  for _, file in ipairs(files) do
    local source_lines = read_lines(file)
    if source_lines then
      local covered, coverable = count_file(source_lines, merged[file].lines)
      if coverable > 0 then
        total_covered = total_covered + covered
        total_coverable = total_coverable + coverable
        local rel = (cwd and file:sub(1, #cwd + 1) == cwd .. "/") and file:sub(#cwd + 2) or file
        rows[#rows + 1] = { name = rel, covered = covered, coverable = coverable }
        width = math.max(width, #rel)
      end
    end
  end

  local lines = {}
  if total_coverable == 0 then
    lines[1] = "Coverage: n/a (no measured lines)"
  else
    lines[1] = ("Coverage: %.1f%% (%d/%d lines)"):format(
      100 * total_covered / total_coverable,
      total_covered,
      total_coverable
    )
    for _, row in ipairs(rows) do
      lines[#lines + 1] = ("  %-" .. (width + 2) .. "s%5.1f%% (%d/%d)"):format(
        row.name,
        100 * row.covered / row.coverable,
        row.covered,
        row.coverable
      )
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
