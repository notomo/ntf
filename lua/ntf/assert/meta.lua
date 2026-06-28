--- @meta

--- @class NtfAssert
--- @field no NtfAssert negated assertions, e.g. `assert.no.equal(want, got)`
--- @field [string] fun(...) custom assertions registered via `ntf.assert.register*`
local M = {}

--- Assert two values are equal (`==`).
--- @param want any: expected value
--- @param got any: actual value
function M.equal(want, got) end

--- Assert two values are deeply equal.
--- @param want any: expected value
--- @param got any: actual value
function M.same(want, got) end

--- Assert `got` is truthy (not `nil` and not `false`).
--- @param got any: value under test
function M.truthy(got) end

--- Assert `got` is falsy (`nil` or `false`).
--- @param got any: value under test
function M.falsy(got) end

--- Assert `got` is exactly `true`.
--- @param got any: value under test
function M.is_true(got) end

--- Assert `got` is exactly `false`.
--- @param got any: value under test
function M.is_false(got) end

--- Assert `got` is `nil`.
--- @param got any: value under test
function M.is_nil(got) end

--- Assert `got` is a string matching the Lua `pattern`.
--- @param pattern string: Lua pattern
--- @param got any: value under test
function M.match(pattern, got) end

return M
