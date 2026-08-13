local tree = require("ntf.core.tree")
local operators = require("ntf.core.mutation.operators")
local oneline = require("ntf.core.controller.report").oneline

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

--- @class NtfMutationBaselineRequest what names the mutant an entry is written for
--- @field path string the file it is in, in any form a command line spells
--- @field row integer 1-based line it starts on
--- @field operator string
--- @field col integer? 0-based start column, naming one of several mutants the row holds
--- @field rationale string why no test can detect it
--- @field invariant_spec string? full name of the test that fails once the rationale stops holding

--- @param sites NtfMutantSite[]
--- @return string # each site on its own indented line, so a message can end with the candidates it rejected
local function listed(sites)
  return table.concat(
    vim.tbl_map(function(site)
      return ("\n  --col=%d %s %s -> %s"):format(
        site.col,
        site.operator,
        oneline(site.original),
        oneline(site.replacement)
      )
    end, sites),
    ""
  )
end

--- @param request NtfMutationBaselineRequest
--- @param cwd string working directory the entry's path is written relative to
--- @return NtfMutationBaselineEntry|string # the entry, or what stopped it being built
function M.build(request, cwd)
  local file = vim.fs.normalize(vim.fn.fnamemodify(request.path, ":p"))
  local f = io.open(file, "r")
  if not f then
    return ("cannot read %s"):format(request.path)
  end
  local src = f:read("*a")
  f:close()

  local root = vim.fs.normalize(cwd)
  if file:sub(1, #root + 1) ~= root .. "/" then
    return ("%s is outside the working directory, which every entry names its file relative to"):format(request.path)
  end
  local relative = file:sub(#root + 2)

  local on_row = vim.tbl_filter(function(site)
    return site.row == request.row
  end, operators.enumerate(src))
  local of_operator = vim.tbl_filter(function(site)
    return site.operator == request.operator
  end, on_row)
  if #of_operator == 0 then
    return ("%s:%d has no %s mutant%s"):format(relative, request.row, request.operator, listed(on_row))
  end

  local candidates = of_operator
  if request.col then
    candidates = vim.tbl_filter(function(site)
      return site.col == request.col
    end, of_operator)
    if #candidates == 0 then
      return ("%s:%d has no %s mutant at col %d%s"):format(
        relative,
        request.row,
        request.operator,
        request.col,
        listed(of_operator)
      )
    end
  end
  if #candidates > 1 then
    return ("%s:%d has %d %s mutants; name one with --col%s"):format(
      relative,
      request.row,
      #candidates,
      request.operator,
      listed(candidates)
    )
  end

  local site = candidates[1]
  local entry = {
    path = relative,
    col = site.col,
    operator = site.operator,
    original = site.original,
    replacement = site.replacement,
    line = vim.split(src, "\n", { plain = true })[site.row],
    rationale = request.rationale,
    invariant_spec = request.invariant_spec,
  }
  local err = M.validate(entry)
  if err then
    return ("the entry %s"):format(err)
  end
  return entry
end

--- @param entries NtfMutationBaselineEntry[]
--- @param entry NtfMutationBaselineEntry
--- @return NtfMutationBaselineEntry[]|string # the entries with it added after the last one naming the same file, or why it was not added
function M.insert(entries, entry)
  local key = key_of(entry.path, entry.line, entry)
  local index = #entries
  for i, existing in ipairs(entries) do
    if key_of(existing.path, existing.line, existing) == key then
      return ("already in the baseline: %s %s %s -> %s"):format(
        entry.path,
        entry.operator,
        oneline(entry.original),
        oneline(entry.replacement)
      )
    end
    if existing.path == entry.path then
      index = i
    end
  end

  local inserted = vim.list_extend({}, entries)
  table.insert(inserted, index + 1, entry)
  return inserted
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
