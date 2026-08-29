local operators = require("ntf.core.mutation.operators")
local absolute = require("ntf.core.path").absolute

local M = {}

--- @class NtfMutationExcludeEntry a path the run leaves out
--- @field path string working-directory-relative file or directory
--- @field operators ("all"|string[])? the operators whose mutants it leaves out; an exclude_spec entry carries none
--- @field rationale string why what it names is left out

local STRING_FIELDS = { "path", "rationale" }

--- @param entry any
--- @return string? # what is wrong with the path and the rationale both kinds of entry carry
local function validate_named_path(entry)
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

--- @param entry any an entry of the exclude_spec section
--- @return string? # what is wrong with the entry
function M.validate_spec(entry)
  local err = validate_named_path(entry)
  if err then
    return err
  end
  if entry.operators ~= nil then
    return "takes no operators, naming a spec rather than a file mutants are enumerated from"
  end
  return nil
end

--- @param entry any an entry of the exclude section
--- @return string? # what is wrong with the entry
function M.validate(entry)
  local err = validate_named_path(entry)
  if err then
    return err
  end
  -- WHY: the whole file is the largest exclusion there is, so it is spelled
  -- rather than defaulted to; an entry that names its operators reads as the
  -- narrower judgement it is, and widening one shows up as a written change.
  -- NOT: taking a missing operators as "all", which makes the largest claim the
  -- shortest thing to write.
  return operators.validate_selection(
    entry.operators,
    'needs an operators of "all" or a non-empty array of operator names'
  )
end

--- @param entries NtfMutationExcludeEntry[]
--- @param cwd string normalized absolute working directory
--- @return string[] # what each entry names, as a normalized absolute path
local function targets_of(entries, cwd)
  return vim.tbl_map(function(entry)
    return absolute(vim.fs.joinpath(cwd, entry.path))
  end, entries)
end

--- @param target string normalized absolute path an entry names
--- @param file string normalized absolute path
--- @return boolean
local function covers(target, file)
  return file == target or file:sub(1, #target + 1) == target .. "/"
end

--- @param entry NtfMutationExcludeEntry
--- @return boolean # whether it leaves the file out whole, rather than one operator's mutants of it
local function is_whole(entry)
  return entry.operators == nil or entry.operators == "all"
end

--- @param files string[] normalized absolute paths
--- @param entries NtfMutationExcludeEntry[]
--- @param cwd string normalized absolute working directory
--- @return string[] # the files no whole-file entry covers, in the given order
--- @return NtfMutationExcludeEntry[] # entries covering no file, in the given order
--- @return string[] # the files a whole-file entry covers, in the given order
function M.partition(files, entries, cwd)
  local targets = targets_of(entries, cwd)

  local covered = {}
  local kept = {}
  local dropped = {}
  for _, file in ipairs(files) do
    local excluded = false
    for index, target in ipairs(targets) do
      if covers(target, file) then
        covered[index] = true
        excluded = excluded or is_whole(entries[index])
      end
    end
    if not excluded then
      table.insert(kept, file)
    else
      table.insert(dropped, file)
    end
  end

  local unused = {}
  for index, entry in ipairs(entries) do
    if not covered[index] then
      table.insert(unused, entry)
    end
  end
  return kept, unused, dropped
end

--- @param entries NtfMutationExcludeEntry[] entries covering nothing the run took
--- @param paths string[] the paths the run discovered specs from, in the form the command line spelled them
--- @param cwd string normalized absolute working directory
--- @return NtfMutationExcludeEntry[] # only the entries one of those paths holds, the rest never having been looked for
function M.within(entries, paths, cwd)
  local roots = vim.tbl_map(function(path)
    return absolute(path)
  end, paths)
  local targets = targets_of(entries, cwd)

  local kept = {}
  for index, entry in ipairs(entries) do
    for _, root in ipairs(roots) do
      if covers(root, targets[index]) then
        table.insert(kept, entry)
        break
      end
    end
  end
  return kept
end

--- @param entries NtfMutationExcludeEntry[]
--- @param cwd string normalized absolute working directory
--- @return fun(file: string, operator: string): boolean # whether an entry leaves that operator's mutants out of the file
function M.operator_filter(entries, cwd)
  local targets = targets_of(entries, cwd)

  local scoped = {}
  for index, entry in ipairs(entries) do
    if not is_whole(entry) then
      table.insert(scoped, { target = targets[index], operators = entry.operators })
    end
  end

  return function(file, operator)
    for _, entry in ipairs(scoped) do
      if covers(entry.target, file) and vim.tbl_contains(entry.operators, operator) then
        return true
      end
    end
    return false
  end
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
