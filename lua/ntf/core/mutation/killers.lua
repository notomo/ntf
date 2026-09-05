local M = {}

--- @param path string normalized absolute path of the mutated file
--- @param mutant { row: integer, col: integer, operator: string, replacement: string }
--- @return string # what names that mutant across runs, its position and what it became
local function key(path, mutant)
  return ("%s\0%d\0%d\0%s\0%s"):format(path, mutant.row, mutant.col, mutant.operator, mutant.replacement)
end

--- @param previous NtfMutationResults? what the run before this one filed, nil where no run has filed any
--- @return fun(mutant: NtfMutant): string? # full name of the test that killed that mutant last time, nil for one no run has killed
function M.previous_killer(previous)
  local killers = {} --- @type table<string, string>

  for path, records in pairs(previous and previous.files or {}) do
    for _, record in ipairs(records) do
      killers[key(path, record)] = record.killed_by
    end
  end

  return function(mutant)
    return killers[key(mutant.path, mutant)]
  end
end

return M
