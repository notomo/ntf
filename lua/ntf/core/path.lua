local M = {}

--- @param path string a path or a component of one
--- @return boolean # whether the path's last component is dot-prefixed
function M.is_hidden(path)
  return vim.startswith(vim.fs.basename(path), ".")
end

return M
