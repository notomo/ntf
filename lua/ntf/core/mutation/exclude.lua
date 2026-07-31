local M = {}

--- @class NtfMutationExcludeEntry a path whose mutants the run does not enumerate
--- @field path string working-directory-relative file or directory
--- @field rationale string why its mutants are not worth running

local STRING_FIELDS = { "path", "rationale" }

--- @param entry any
--- @return string? # what is wrong with the entry
function M.validate(entry)
  if type(entry) ~= "table" then
    return "is not an object"
  end
  for _, field in ipairs(STRING_FIELDS) do
    if type(entry[field]) ~= "string" then
      return ("needs a string %s"):format(field)
    end
  end
  if not entry.rationale:find("%S") then
    return "needs a non-empty rationale"
  end
  return nil
end

--- @param files string[] normalized absolute paths
--- @param entries NtfMutationExcludeEntry[]
--- @param cwd string normalized absolute working directory
--- @return string[] # the files no entry covers, in the given order
--- @return NtfMutationExcludeEntry[] # entries covering no file, in the given order
function M.partition(files, entries, cwd)
  local targets = vim.tbl_map(function(entry)
    return (vim.fs.normalize(vim.fs.joinpath(cwd, entry.path)):gsub("/$", ""))
  end, entries)

  local covered = {}
  local kept = {}
  for _, file in ipairs(files) do
    local excluded = false
    for index, target in ipairs(targets) do
      if file == target or file:sub(1, #target + 1) == target .. "/" then
        covered[index] = true
        excluded = true
      end
    end
    if not excluded then
      table.insert(kept, file)
    end
  end

  local unused = {}
  for index, entry in ipairs(entries) do
    if not covered[index] then
      table.insert(unused, entry)
    end
  end
  return kept, unused
end

return M
