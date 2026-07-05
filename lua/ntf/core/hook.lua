local M = {}

--- @class NtfHook
--- @field setup fun()
--- @field teardown fun()

--- @class NtfHookModule
--- @field setup fun()?
--- @field teardown fun()?

local function noop() end

--- @param path string?
--- @return NtfHook
function M.load(path)
  --- @type NtfHookModule
  local loaded = {}
  if type(path) == "string" and path ~= "" then
    local result = dofile(path)
    if type(result) == "table" then
      loaded = result
    end
  end
  return {
    setup = loaded.setup or noop,
    teardown = loaded.teardown or noop,
  }
end

return M
