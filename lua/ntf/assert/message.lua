local M = {}

local store = {}

--- @param key string
--- @param message string
function M.set(_, key, message)
  store[key] = message
end

--- @param key string
--- @return string|nil
function M.get(key)
  return store[key]
end

return M
