local M = {}

--- @class NtfMutationExcludeEntry a path the run leaves out
--- @field path string working-directory-relative file or directory
--- @field rationale string why what it names is left out

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

--- @param items NtfWorkItem[] work items, in the order the run dispatches them
--- @param entries NtfMutationExcludeEntry[] spec paths whose tests do not drive the mutants
--- @param cwd string working directory
--- @return table<integer, true> # indexes of the items declared in a covered spec file
function M.item_indexes(items, entries, cwd)
  local files = vim.tbl_map(function(item)
    return item.file
  end, items)
  local kept_files = M.partition(files, entries, cwd)

  local kept = {}
  for _, file in ipairs(kept_files) do
    kept[file] = true
  end

  local indexes = {}
  for index, item in ipairs(items) do
    if not kept[item.file] then
      indexes[index] = true
    end
  end
  return indexes
end

return M
