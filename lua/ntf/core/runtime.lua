-- Shared runtime setup performed before loading any spec, in both the controller
-- and the workers: put the cwd (the plugin under test) on the runtimepath so the
-- plugin and its `test/helper` are requirable.
local M = {}

function M.setup()
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
end

return M
