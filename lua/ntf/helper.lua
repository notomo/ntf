-- `ntf.helper` is the replacement for `vusted.helper` (pure vim, no luarocks):
-- small utilities used by per-plugin test helpers.
local M = {}

local _adjust_sep
if vim.fn.has("win32") == 1 then
  _adjust_sep = function(path)
    return path:gsub("\\", "/")
  end
else
  _adjust_sep = function(path)
    return path
  end
end

--- Returns plugin root directory full path.
--- @param plugin_name string: lua module name (`lua/{plugin_name}/*.lua`)
--- @return string # plugin root directory full path
function M.find_plugin_root(plugin_name)
  local root_pattern = ("lua/%s/*"):format(plugin_name)
  local file = vim.api.nvim_get_runtime_file(root_pattern, false)[1]
  if file == nil then
    error("plugin root is not found by pattern: " .. root_pattern)
  end
  return vim.split(_adjust_sep(file), "/lua/", { plain = true })[1]
end

--- Returns root module name.
--- For example, `get_module_root("plugin_name.module1")` returns `plugin_name`.
--- @param module_name string: lua module name
--- @return string # root module name
function M.get_module_root(module_name)
  return vim.split(module_name:gsub("%.", "/"), "/", { plain = true })[1]
end

return M
