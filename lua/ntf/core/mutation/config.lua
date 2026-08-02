local M = {}

local VERSION = 1

--- @class NtfMutationConfig the mutation policy a run is given
--- @field baseline NtfMutationBaselineEntry[] mutants judged impossible to kill
--- @field exclude NtfMutationExcludeEntry[] paths whose mutants the run does not enumerate
--- @field exclude_spec NtfMutationExcludeEntry[] spec paths the run still runs, but never picks as a mutant's trial

--- @param decoded table
--- @param key string name of the section in the document
--- @param validate fun(entry: any): string? what is wrong with one of its entries
--- @return table[]|string # the section's entries, or a string saying what is wrong with it
local function load_section(decoded, key, validate)
  local entries = decoded[key]
  if entries == nil then
    return {}
  end
  if type(entries) ~= "table" then
    return ("%s is not an array"):format(key)
  end
  for index, entry in ipairs(entries) do
    local err = validate(entry)
    if err then
      return ("%s[%d] %s"):format(key, index, err)
    end
  end
  return entries
end

--- @param path string
--- @return NtfMutationConfig|string # the config, or an error message
function M.load(path)
  local invalid = function(message)
    return ("--mutation-config %s: %s"):format(path, message)
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

  local baseline = load_section(decoded, "baseline", require("ntf.core.mutation.baseline").validate)
  if type(baseline) == "string" then
    return invalid(baseline)
  end
  local validate_exclude = require("ntf.core.mutation.exclude").validate
  local exclude = load_section(decoded, "exclude", validate_exclude)
  if type(exclude) == "string" then
    return invalid(exclude)
  end
  local exclude_spec = load_section(decoded, "exclude_spec", validate_exclude)
  if type(exclude_spec) == "string" then
    return invalid(exclude_spec)
  end

  return { baseline = baseline, exclude = exclude, exclude_spec = exclude_spec } --[[@as NtfMutationConfig]]
end

return M
