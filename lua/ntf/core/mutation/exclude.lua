local M = {}

local VERSION = 1

--- @class NtfMutationExcludeEntry a path whose mutants the run does not enumerate
--- @field path string working-directory-relative file or directory
--- @field rationale string why its mutants are not worth running

local STRING_FIELDS = { "path", "rationale" }

--- @param entry any
--- @return string? # what is wrong with the entry
local function validate(entry)
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

--- @param path string
--- @return NtfMutationExcludeEntry[]|string # entries, or an error message
function M.load(path)
  local invalid = function(message)
    return ("--mutation-exclude %s: %s"):format(path, message)
  end

  local f = io.open(path, "r")
  if not f then
    return invalid("cannot be read")
  end
  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return invalid("invalid JSON: " .. decoded)
  end
  if type(decoded) ~= "table" or decoded.version ~= VERSION then
    return invalid(("expected version %d"):format(VERSION))
  end
  if type(decoded.entries) ~= "table" then
    return invalid("expected an entries array")
  end
  for index, entry in ipairs(decoded.entries) do
    local err = validate(entry)
    if err then
      return invalid(("entries[%d] %s"):format(index, err))
    end
  end
  return decoded.entries
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
