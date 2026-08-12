local M = {}

local VERSION = 1

--- @class NtfMutationConfig the mutation policy a run is given
--- @field operators NtfMutationOperatorSelection the operators the run enumerates mutants for, spelled rather than defaulted so an operator added upstream reaches the run only once it is named
--- @field baseline NtfMutationBaselineEntry[] mutants judged impossible to kill
--- @field exclude NtfMutationExcludeEntry[] paths whose mutants the run leaves out, whole or by operator
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

  local selection_err = require("ntf.core.mutation.operators").validate_selection(
    decoded.operators,
    'needs to be "all" or a non-empty array of operator names'
  )
  if selection_err then
    return invalid("operators " .. selection_err)
  end

  local baseline = load_section(decoded, "baseline", require("ntf.core.mutation.baseline").validate)
  if type(baseline) == "string" then
    return invalid(baseline)
  end
  local exclude_module = require("ntf.core.mutation.exclude")
  local exclude = load_section(decoded, "exclude", exclude_module.validate)
  if type(exclude) == "string" then
    return invalid(exclude)
  end
  local exclude_spec = load_section(decoded, "exclude_spec", exclude_module.validate_spec)
  if type(exclude_spec) == "string" then
    return invalid(exclude_spec)
  end

  return { operators = decoded.operators, baseline = baseline, exclude = exclude, exclude_spec = exclude_spec } --[[@as NtfMutationConfig]]
end

local INDENT = "  "

--- @type { key: string, fields: string[] }[] the sections in the order the document carries them, each with the order its entries spell their fields in
local SECTIONS = {
  {
    key = "baseline",
    fields = { "path", "col", "operator", "original", "replacement", "line", "rationale", "invariant_spec" },
  },
  { key = "exclude", fields = { "path", "operators", "rationale" } },
  { key = "exclude_spec", fields = { "path", "rationale" } },
}

--- @param value string|number|string[]
--- @param indent string what the line the value starts on is indented by
--- @return string
local function encode(value, indent)
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end
  local inner = indent .. INDENT
  local items = vim.tbl_map(function(item)
    return inner .. vim.json.encode(item)
  end, value)
  return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
end

--- @param entry table
--- @param fields string[]
--- @param indent string
--- @return string
local function encode_entry(entry, fields, indent)
  local inner = indent .. INDENT
  local written = {}
  for _, field in ipairs(fields) do
    if entry[field] ~= nil then
      table.insert(written, ("%s%s: %s"):format(inner, vim.json.encode(field), encode(entry[field], inner)))
    end
  end
  return "{\n" .. table.concat(written, ",\n") .. "\n" .. indent .. "}"
end

--- @param config NtfMutationConfig
--- @return string # the document text, in the one shape every write produces, so an edit shows up as the entry it changed
function M.format(config)
  local written = {
    ('%s"version": %d'):format(INDENT, VERSION),
    ('%s"operators": %s'):format(INDENT, encode(config.operators, INDENT)),
  }
  for _, section in ipairs(SECTIONS) do
    local entries = config[section.key]
    if #entries > 0 then
      local encoded = vim.tbl_map(function(entry)
        return INDENT .. INDENT .. encode_entry(entry, section.fields, INDENT .. INDENT)
      end, entries)
      table.insert(
        written,
        ("%s%s: [\n%s\n%s]"):format(INDENT, vim.json.encode(section.key), table.concat(encoded, ",\n"), INDENT)
      )
    end
  end
  return "{\n" .. table.concat(written, ",\n") .. "\n}\n"
end

--- @param path string
--- @param config NtfMutationConfig
function M.write(path, config)
  local file = assert(io.open(path, "w"))
  file:write(M.format(config))
  file:close()
end

return M
