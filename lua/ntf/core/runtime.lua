local M = {}

--- @param process_hook string? Lua module whose setup this process runs before it loads a spec
--- @return string? # why the module cannot be one, the hook left unrun
function M.setup(process_hook)
  -- WHY: nvim reads the argument as runtimepath's own grammar: a comma splits
  -- the entry, and where the path separator is not the backslash, a backslash
  -- escapes and a `$` expands. A working directory holding any of them is
  -- therefore prepended as some other path.
  -- NOT: escaping it into one option entry, which branches on the platform for
  -- what the backslash means and has to reach every path ntf prepends, for
  -- directory names no project is given.
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  local setup = require("ntf.core.hook").load_setup(process_hook)
  if type(setup) == "string" then
    return setup
  end
  setup()
end

return M
