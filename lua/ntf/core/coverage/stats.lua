-- Writes merged coverage counts in LuaCov's `luacov.stats.out` format, so the
-- mature LuaCov reporter (or any compatible tool) can render an authoritative
-- report from ntf's data. ntf has no dependency on LuaCov; it only emits the
-- file. The format, per measured file, is two lines:
--   <max>:<path>\n
--   <hits_1> <hits_2> ... <hits_max> \n   (a line never hit is written as 0)
-- LuaCov reads the leading <max> with `read("*n")` and then that many numbers,
-- so trailing spaces and the exact separators are not significant.
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

return M
