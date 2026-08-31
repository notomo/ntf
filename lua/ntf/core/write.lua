local M = {}

-- WHY: workers file their own copies under one cache directory at the same
-- moment, and mkdir raises E739 at whichever of them meets a level created since
-- it looked. One level at a time, that raise says the level is there, which the
-- levels below it are still made after.
-- NOT: mkdir(dir, "p"), whose raise for one level leaves every deeper one unmade,
-- pcall or no pcall.
--- @param dir string
local function make_dir(dir)
  local parent = vim.fs.dirname(dir)
  if parent ~= dir then
    make_dir(parent)
  end
  pcall(vim.fn.mkdir, dir)
end

--- @param path string output path, whose directory is created when it is missing
--- @param content string
function M.file(path, content)
  make_dir(vim.fs.dirname(path))

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
