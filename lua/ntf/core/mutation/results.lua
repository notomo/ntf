local M = {}

local VERSION = 1

--- @class NtfMutationResults
--- @field version integer
--- @field score number? percent detected; absent when nothing was scoreable
--- @field counts table<string, integer>
--- @field files table<string, NtfMutationResultRecord[]> normalized absolute path -> records

--- @class NtfMutationResultRecord
--- @field row integer 1-based start line
--- @field col integer 0-based start column
--- @field end_row integer 1-based end line
--- @field end_col integer 0-based end column, exclusive
--- @field operator string
--- @field original string
--- @field replacement string
--- @field status "killed"|"timeout"|"survived"|"no_coverage"|"not_applied"
--- @field killed_by string?

--- @param path string output path
--- @param summary NtfMutationSummary
function M.write(path, summary)
  local files = {}
  for _, record in ipairs(summary.records) do
    local mutant = record.mutant
    local records = files[mutant.path]
    if not records then
      records = {}
      files[mutant.path] = records
    end
    table.insert(records, {
      row = mutant.row,
      col = mutant.col,
      end_row = mutant.end_row,
      end_col = mutant.end_col,
      operator = mutant.operator,
      original = mutant.original,
      replacement = mutant.replacement,
      status = record.status,
      killed_by = record.killed_by,
    })
  end

  for _, records in pairs(files) do
    table.sort(records, function(a, b)
      if a.row ~= b.row then
        return a.row < b.row
      end
      if a.col ~= b.col then
        return a.col < b.col
      end
      return a.operator < b.operator
    end)
  end

  local f = assert(io.open(path, "w"))
  f:write(vim.json.encode({
    version = VERSION,
    score = summary.score,
    counts = summary.counts,
    -- An empty Lua table encodes as `[]`, which would not decode back as a map.
    files = next(files) and files or vim.empty_dict(),
  }))
  f:close()
end

--- @param path string
--- @return NtfMutationResults? # nil when the file does not exist or is not readable
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end
  return decoded
end

return M
