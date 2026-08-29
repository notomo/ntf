local M = {}

--- @param path string a path or a component of one
--- @return boolean # whether the path's last component is dot-prefixed
function M.is_hidden(path)
  return vim.startswith(vim.fs.basename(path), ".")
end

--- @param path string a path as the platform spells it
--- @return string # the path spelled with "/" separators, an upper-case Windows drive letter, no "." or ".." component and no trailing separator
function M.normalize(path)
  local slashed = path:gsub("\\", "/"):gsub("^%a:", string.upper)
  local root = vim.startswith(slashed, "/") and "/" or ""

  local parts = {}
  for part in vim.gsplit(slashed, "/") do
    if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
      table.remove(parts)
    elseif part ~= "" and part ~= "." and (part ~= ".." or root == "") then
      table.insert(parts, part)
    end
  end
  return root .. table.concat(parts, "/")
end

-- WHY: vim.fs reads a "$VAR" component of a path as the variable it names, and the plain=true that
-- turns that off is on Neovim master only, so a released Neovim reads such a path as another
-- directory's or as none at all. vim.fn.fnamemodify() reads a path as a path on every version, and
-- M.normalize folds the rest of the spelling above.
-- NOT: vim.fs.normalize(vim.fn.fnamemodify(path, ":p"), { plain = true })

--- @param path string a path in any form
--- @return string # the normalized absolute path it names
function M.absolute(path)
  return M.normalize(vim.fn.fnamemodify(path, ":p"))
end

--- @param path string a path in any form
--- @param base string the directory to write it relative to, in any form
--- @return string # the normalized path below base, cut at base's own separator so that a sibling whose name merely starts with base keeps the path it has; the whole path where base does not hold it
function M.relative(path, base)
  local normalized = M.normalize(path)
  local root = M.absolute(base)
  if normalized:sub(1, #root + 1) == root .. "/" then
    return normalized:sub(#root + 2)
  end
  return normalized
end

return M
