local M = {}

local VERSION = 1

--- @class NtfMutationBaselineEntry a mutant judged impossible to kill
--- @field path string working-directory-relative path of the mutated file
--- @field col integer 0-based start column
--- @field operator string
--- @field original string
--- @field replacement string
--- @field line string exact text of the mutant's start line
--- @field rationale string why no test can detect the mutant

-- An entry names its mutant by the line's text rather than its number: a row
-- shifts under any edit above it, while the text pins the judged code itself,
-- so the mark dies exactly when the judgement needs remaking.
--- @param path string working-directory-relative path
--- @param line string text of the mutant's start line
--- @param site { col: integer, operator: string, original: string, replacement: string }
--- @return string
local function key_of(path, line, site)
  return table.concat({ path, site.col, site.operator, site.original, site.replacement, line }, "\0")
end

local STRING_FIELDS = { "path", "operator", "original", "replacement", "line", "rationale" }

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
  if type(entry.col) ~= "number" then
    return "needs a number col"
  end
  if not entry.rationale:find("%S") then
    return "needs a non-empty rationale"
  end
  return nil
end

--- @param path string
--- @return NtfMutationBaselineEntry[]|string # entries, or an error message
function M.load(path)
  local invalid = function(message)
    return ("--mutation-baseline %s: %s"):format(path, message)
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

--- @param entries NtfMutationBaselineEntry[]
--- @return { match: (fun(relative_path: string, line: string, site: NtfMutantSite): NtfMutationBaselineEntry?), lost: (fun(): NtfMutationBaselineEntry[]) }
function M.matcher(entries)
  local by_key = {} --- @type table<string, NtfMutationBaselineEntry[]>
  for _, entry in ipairs(entries) do
    local key = key_of(entry.path, entry.line, entry)
    local bucket = by_key[key] or {}
    table.insert(bucket, entry)
    by_key[key] = bucket
  end

  local matched = {} --- @type table<NtfMutationBaselineEntry, true>
  return {
    match = function(relative_path, line, site)
      local bucket = by_key[key_of(relative_path, line, site)]
      if not bucket then
        return nil
      end
      for _, entry in ipairs(bucket) do
        matched[entry] = true
      end
      return bucket[1]
    end,
    lost = function()
      return vim.tbl_filter(function(entry)
        return not matched[entry]
      end, entries)
    end,
  }
end

return M
