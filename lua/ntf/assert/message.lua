-- Assertion message store: an assertion sets a fully-formed message by key just
-- before it is evaluated, and the message is looked up by key on failure. No
-- placeholder formatting is needed, so storing the raw string is enough.
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
