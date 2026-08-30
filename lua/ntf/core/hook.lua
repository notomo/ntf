local M = {}

--- @class NtfHook
--- @field setup fun()
--- @field teardown fun()

--- @class NtfHookModule
--- @field setup fun()?
--- @field teardown fun()?

local function noop() end

--- @type string[] every key a hook module may carry
local HOOK_KEYS = { "setup", "teardown" }

--- @param result any what the module returned
--- @param path string the file it was read from
--- @return string? # why it cannot be a hook module
local function rejected(result, path)
  if type(result) ~= "table" then
    return ("%s returns a %s: a hook module returns a table of hooks, as in `return { setup = function() end }`."):format(
      path,
      type(result)
    )
  end
  local known = {}
  for _, key in ipairs(HOOK_KEYS) do
    known[key] = true
    local value = result[key]
    if value ~= nil and type(value) ~= "function" then
      return ("%s gives its %s a %s: a hook is a function."):format(path, key, type(value))
    end
  end
  local unknown = {}
  for key in pairs(result) do
    if not known[key] then
      table.insert(unknown, tostring(key))
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    return ("%s returns keys no hook is read from: %s. A hook module takes %s."):format(
      path,
      table.concat(unknown, ", "),
      table.concat(HOOK_KEYS, " and ")
    )
  end
  return nil
end

--- @param path string?
--- @return NtfHookModule|string # the module's hooks, or why the file cannot be one
local function load_module(path)
  if type(path) ~= "string" or path == "" then
    return {}
  end
  local result = dofile(path)
  return rejected(result, path) or result
end

--- @param path string?
--- @return NtfHook|string # the hooks, each missing one filled with a noop, or why the module cannot be one
function M.load(path)
  local loaded = load_module(path)
  if type(loaded) == "string" then
    return loaded
  end
  return {
    setup = loaded.setup or noop,
    teardown = loaded.teardown or noop,
  }
end

--- @param path string?
--- @return fun()|string # the setup every process runs before it loads a spec, or why the module cannot be one
function M.load_setup(path)
  local loaded = load_module(path)
  if type(loaded) == "string" then
    return loaded
  end
  if loaded.teardown ~= nil then
    return ("--process-hook takes no teardown: %s. It says what a process is, not what it brackets, so a teardown belongs in --test-hook, which brackets each test in its worker, or in --global-hook, which brackets the whole run in the launcher."):format(
      path
    )
  end
  return loaded.setup or noop
end

return M
