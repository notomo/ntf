-- Shared runtime setup performed before loading any spec, in both the controller
-- and the workers: put the cwd (the plugin under test) on the runtimepath so the
-- plugin and its `test/helper` are requirable.
local M = {}

function M.setup()
  vim.opt.runtimepath:prepend(vim.fn.getcwd())

  -- Opt-in compatibility for running not-yet-migrated specs that still require
  -- the vusted helper/assert modules. Off by default (ntf ships `ntf.*` only).
  if vim.env.NTF_COMPAT_VUSTED then
    package.preload["vusted.helper"] = function()
      return require("ntf.helper")
    end
    package.preload["vusted.assert"] = function()
      return require("ntf.assert")
    end
  end
end

return M
