local M = {}

--- @param path string output path, whose directory is created when it is missing
--- @param content string
function M.file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  -- WHY: another ntf run on the same project reads this path while this one
  -- writes it, so it has to find either the whole old file or the whole new
  -- one. The rename is atomic within the directory.
  -- NOT: opening path itself, which truncates it and leaves that reader the
  -- half-written file until the write lands.
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  local file = assert(io.open(tmp, "w"))
  file:write(content)
  file:close()
  assert(vim.uv.fs_rename(tmp, path))
end

return M
