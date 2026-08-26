local M = {}

--- @param process_hook string? Lua module whose setup this process runs before it loads a spec
--- @return string? # why the module cannot be one, the hook left unrun
function M.setup(process_hook)
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  local setup = require("ntf.core.hook").load_setup(process_hook)
  if type(setup) == "string" then
    return setup
  end
  setup()
end

return M
