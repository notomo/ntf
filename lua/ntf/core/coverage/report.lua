local coverable_lines = require("ntf.core.coverage.lines").coverable

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

--- @param source_lines string[]
--- @param hits table<integer, integer>
--- @return integer covered, integer coverable, integer[] missed ascending line numbers
local function count_file(source_lines, hits)
  local seen = {}
  for line in pairs(hits) do
    seen[line] = true
  end
  for line in pairs(coverable_lines(table.concat(source_lines, "\n"))) do
    seen[line] = true
  end

  local coverable = vim.tbl_keys(seen)
  table.sort(coverable)

  local covered, missed = 0, {}
  for _, line in ipairs(coverable) do
    if (hits[line] or 0) > 0 then
      covered = covered + 1
    else
      missed[#missed + 1] = line
    end
  end
  return covered, #coverable, missed
end

--- @param rows integer[] ascending line numbers
--- @return string # comma-separated; a run of consecutive rows is written "first-last"
local function ranges(rows)
  local parts = {}
  local first = rows[1]
  for i, row in ipairs(rows) do
    local next_row = rows[i + 1]
    if next_row ~= row + 1 then
      parts[#parts + 1] = first == row and tostring(row) or ("%d-%d"):format(first, row)
      first = next_row
    end
  end
  return table.concat(parts, ",")
end

--- @param merged table<string, { max: integer, lines: table<integer, integer> }>
--- @param cwd string? working directory, to show file paths relative to it
--- @return string
--- @return boolean # whether it found a line to hold the tests to: a run that measured none has no coverage to report, however green it looks
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
      local covered, coverable, missed = count_file(source_lines, merged[file].lines)
      if coverable > 0 then
        total_covered = total_covered + covered
        total_coverable = total_coverable + coverable
        local rel = (cwd and file:sub(1, #cwd + 1) == cwd .. "/") and file:sub(#cwd + 2) or file
        rows[#rows + 1] = { name = rel, covered = covered, coverable = coverable, missed = missed }
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
      local name = row.name .. (" "):rep(width + 2 - #row.name)
      local line = ("  %s%5.1f%% (%d/%d)"):format(name, 100 * row.covered / row.coverable, row.covered, row.coverable)
      if row.covered > 0 and #row.missed > 0 then
        line = line .. "  missed: " .. ranges(row.missed)
      end
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, "\n") .. "\n", total_coverable > 0
end

return M
