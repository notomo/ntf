local M = {}

--- @class NtfMutationCoverageMap
--- @field add fun(item_index: integer, coverage: table?, loaded: string[]?) record one worker's line hits and the files it loaded
--- @field item_indexes fun(path: string, rows: integer[]): integer[] items that hit any of the rows
--- @field loaded_files fun(item_index: integer): string[] the files the item's worker loaded, which its verdict on a mutant depends on

--- @param opts { ignore_items: table<integer, true>? }? item indexes whose coverage the map drops, so their tests are never picked as trials
--- @return NtfMutationCoverageMap which tests reach which lines, so a mutant is only run against the tests that can possibly detect it
function M.new(opts)
  local ignore_items = (opts or {}).ignore_items or {}

  --- @type table<string, table<integer, table<integer, true>>>
  local by_path = {}
  --- @type table<integer, string[]>
  local loaded_by_item = {}

  local function add(item_index, coverage, loaded)
    if ignore_items[item_index] then
      return
    end
    loaded_by_item[item_index] = loaded or {}
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

  local function loaded_files(item_index)
    return loaded_by_item[item_index] or {}
  end

  return { add = add, item_indexes = item_indexes, loaded_files = loaded_files }
end

return M
