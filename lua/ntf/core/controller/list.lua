local report = require("ntf.core.controller.report")
local tree = require("ntf.core.tree")

local M = {}

--- @param items NtfWorkItem[]
--- @return string # one "path:line: full name" line per test
function M.tests(items)
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, ("%s: %s"):format(report.rel_source(item.trace), tree.full_name(item.names)))
  end
  return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

--- @param entry NtfMutantListEntry
--- @return string
local function annotation(entry)
  if entry.equivalent then
    return "equivalent"
  end
  if entry.covered_count == 0 then
    return "no coverage"
  end
  return ("covered by %d test%s"):format(entry.covered_count, entry.covered_count == 1 and "" or "s")
end

--- @param entries NtfMutantListEntry[]
--- @return string # one "path:row:col: operator: original -> replacement (annotation)" line per mutant
function M.mutants(entries)
  local lines = {}
  for _, entry in ipairs(entries) do
    local mutant = entry.mutant
    table.insert(
      lines,
      ("%s:%d:%d: %s: %s -> %s (%s)"):format(
        entry.relative_path,
        mutant.row,
        mutant.col,
        mutant.operator,
        mutant.original,
        mutant.replacement,
        annotation(entry)
      )
    )
  end
  return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

--- @param load_errors NtfLoadError[]
--- @return string
function M.load_errors(load_errors)
  local paint = report.painter(false)
  local lines = {}
  for _, load_error in ipairs(load_errors) do
    vim.list_extend(lines, report.load_error_block(load_error, paint))
  end
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

return M
