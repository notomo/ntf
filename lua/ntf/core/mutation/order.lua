local M = {}

--- @param tasks NtfMutantTask[]
--- @return integer[] # a permutation of the task indexes, slowest first
function M.order(tasks)
  local keyed = {}
  for index, task in ipairs(tasks) do
    table.insert(keyed, { ms = task.trials[1].baseline_ms, index = index })
  end
  table.sort(keyed, function(a, b)
    if a.ms ~= b.ms then
      return a.ms > b.ms
    end
    return a.index < b.index
  end)
  return vim.tbl_map(function(k)
    return k.index
  end, keyed)
end

return M
