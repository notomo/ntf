local M = {}

--- @param path string output file path
--- @param merged table<string, { max: integer, lines: table<integer, integer> }>
function M.write(path, merged)
  local files = vim.tbl_keys(merged)
  table.sort(files)

  local out = {}
  for _, file in ipairs(files) do
    local entry = merged[file]
    out[#out + 1] = ("%d:%s"):format(entry.max, file)
    local counts = {}
    for i = 1, entry.max do
      counts[i] = tostring(entry.lines[i] or 0)
    end
    out[#out + 1] = table.concat(counts, " ")
  end

  local f = assert(io.open(path, "w"))
  if #out > 0 then
    f:write(table.concat(out, "\n"), "\n")
  end
  f:close()
end

--- @param path string stats file path
--- @return table<string, { max: integer, lines: table<integer, integer> }>
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end

  local merged = {}
  while true do
    local header = f:read("*l")
    if not header then
      break
    end
    local max, file = header:match("^(%d+):(.*)$")
    local counts = f:read("*l")
    if max and counts then
      local lines = {}
      local i = 0
      for n in counts:gmatch("%S+") do
        i = i + 1
        lines[i] = tonumber(n)
      end
      merged[file] = { max = tonumber(max), lines = lines }
    end
  end
  f:close()
  return merged
end

return M
