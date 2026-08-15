local M = {}

--- @param path string output path, whose directory is created when it is missing
--- @param content string
function M.file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

return M
