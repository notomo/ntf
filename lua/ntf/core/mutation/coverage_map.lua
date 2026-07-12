local M = {}

--- @class NtfMutationCoverageMap
--- @field add fun(item_index: integer, coverage: table?) record one worker's line hits
--- @field item_indexes fun(path: string, rows: integer[]): integer[] items that hit any of the rows

--- Which tests reach which lines, so a mutant is only run against the tests that
--- can possibly detect it.
--- @return NtfMutationCoverageMap
function M.new()
  --- @type table<string, table<integer, table<integer, true>>>
  local by_path = {}

  local function add(item_index, coverage)
    for path, entry in pairs(coverage or {}) do
      local lines = by_path[path]
      if not lines then
        lines = {}
        by_path[path] = lines
      end
      for line in pairs(entry.lines or {}) do
        local row = tonumber(line)
        if row then
          local items = lines[row]
          if not items then
            items = {}
            lines[row] = items
          end
          items[item_index] = true
        end
      end
    end
  end

  local function item_indexes(path, rows)
    local lines = by_path[path]
    if not lines then
      return {}
    end

    local seen = {}
    for _, row in ipairs(rows) do
      for item_index in pairs(lines[row] or {}) do
        seen[item_index] = true
      end
    end

    local indexes = vim.tbl_keys(seen)
    table.sort(indexes)
    return indexes
  end

  return { add = add, item_indexes = item_indexes }
end

return M
