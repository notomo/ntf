local M = {}

--- @type integer[] the oldest Neovim ntf runs on
M.required = { 0, 12, 0 }

--- @return string # the requirement as the documents and the message below spell it
function M.required_text()
  return table.concat(M.required, ".")
end

--- @param current vim.Version what this Neovim reports
--- @return string? # why it cannot run ntf, nil when it can
function M.unsupported(current)
  if not vim.version.lt(current, M.required) then
    return nil
  end
  return ("ntf needs Neovim %s or later, but this one is %s (set $NTF_NVIM to name another binary)"):format(
    M.required_text(),
    tostring(current)
  )
end

return M
