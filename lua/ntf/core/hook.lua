local M = {}

--- @class NtfHook
--- @field setup fun()
--- @field teardown fun()

--- @class NtfHookModule
--- @field setup fun()?
--- @field teardown fun()?

local function noop() end

--- @param path string?
--- @return NtfHookModule
local function load_module(path)
  if type(path) ~= "string" or path == "" then
    return {}
  end
  local result = dofile(path)
  if type(result) ~= "table" then
    return {}
  end
  return result
end

--- @param path string?
--- @return NtfHook
function M.load(path)
  local loaded = load_module(path)
  return {
    setup = loaded.setup or noop,
    teardown = loaded.teardown or noop,
  }
end

--- @param path string?
--- @return fun()|string # the setup every process runs before it loads a spec, or why the module cannot be one
function M.load_setup(path)
  local loaded = load_module(path)
  if loaded.teardown ~= nil then
    return ("--process-hook takes no teardown: %s. It says what a process is, not what it brackets, so a teardown belongs in --test-hook, which brackets each test in its worker, or in --global-hook, which brackets the whole run in the launcher."):format(
      path
    )
  end
  return loaded.setup or noop
end

return M
