local M = {}

--- @class NtfWalkHandlers
--- @field descend fun(dir: string): boolean whether the walk goes on into that subdirectory
--- @field on_file fun(file: string) takes each entry that is not a directory, a symlink included

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
      opts.on_file(child)
    end
  end
end

return M
