local M = {}

--- @param path string a path or a component of one
--- @return boolean # whether the path's last component is dot-prefixed
function M.is_hidden(path)
  return vim.startswith(vim.fs.basename(path), ".")
end

--- @param path string an absolute path as the platform spells it
--- @return string # the path spelled with "/" separators, an upper-case Windows drive letter and no trailing separator
function M.normalize(path)
  local slashed = path:gsub("\\", "/"):gsub("^%a:", string.upper)
  return (slashed:gsub("(.)/$", "%1"))
end

return M
