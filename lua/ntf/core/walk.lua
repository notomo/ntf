local M = {}

--- @class NtfWalkHandlers
--- @field descend fun(dir: string): boolean whether the walk goes on into that subdirectory
--- @field on_file fun(file: string, ftype: string) takes each entry that is not a directory, with its `vim.fn.getftype`

--- @param dir string normalized absolute directory
--- @param opts NtfWalkHandlers
function M.files(dir, opts)
  for _, name in ipairs(vim.fn.readdir(dir)) do
    local child = vim.fs.joinpath(dir, name)
    local ftype = vim.fn.getftype(child)
    if ftype == "dir" then
      if opts.descend(child) then
        M.files(child, opts)
      end
    else
      opts.on_file(child, ftype)
    end
  end
end

return M
