local tree = require("ntf.core.tree")

local M = {}

--- @class NtfMutationBaselineEntry a mutant judged impossible to kill
--- @field path string working-directory-relative path of the mutated file
--- @field col integer 0-based start column
--- @field operator string
--- @field original string
--- @field replacement string
--- @field line string exact text of the mutant's start line
--- @field rationale string why no test can detect the mutant
--- @field invariant_spec string? full name of the test that fails once the rationale stops holding

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
function M.validate(entry)
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
  if entry.invariant_spec ~= nil then
    if type(entry.invariant_spec) ~= "string" or not entry.invariant_spec:find("%S") then
      return "needs a non-empty string invariant_spec, or none at all"
    end
  end
  return nil
end

--- @param entries NtfMutationBaselineEntry[]
--- @param results NtfResult[] the results of the run the mutants were enumerated from
--- @return NtfMutationBaselineEntry[] # entries whose invariant_spec names no test that passed
function M.unpinned(entries, results)
  local passed = {} --- @type table<string, true>
  for _, result in ipairs(results) do
    if result.status == "passed" then
      passed[tree.full_name(result.names)] = true
    end
  end
  return vim.tbl_filter(function(entry)
    return entry.invariant_spec ~= nil and not passed[entry.invariant_spec]
  end, entries)
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
