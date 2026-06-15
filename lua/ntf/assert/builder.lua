-- Builds the assert object: the `assert.equal(...)` / `assert.no.X(...)` DSL and
-- `:register`. It reimplements only the luassert behavior the existing specs rely
-- on, with no luarocks dependency. Each assertion has a single spelling and the
-- one negation word `no` (no luassert-style modifier chains). Custom assertions
-- are registered through `:register` (used by `ntf.assert` / assertlib); built-in
-- assertions are pre-registered below.
local message = require("ntf.assert.message")

local M = {}

--- @class NtfAssertionEntry
--- @field callback fun(state: table, args: any[]): any returns truthy when the assertion holds
--- @field positive string? message key used when expected positive
--- @field negative string? message key used when negated

-- the single negation word: `assert.no.X(...)` flips the expectation
local negations = {
  ["no"] = true,
}

--- @param registry table<string, NtfAssertionEntry> shared assertion registry
--- @param positive boolean current expectation (false = negated)
local function new_state(registry, positive)
  local state = { mod = positive }

  local function run(entry, ...)
    local args = { ... }
    local ok = entry.callback(state, args)
    local passed = (not not ok) == positive
    if passed then
      return ...
    end
    local key = positive and entry.positive or entry.negative
    local failed = (key and message.get(key)) or "assertion failed!"
    error(failed, 2)
  end

  return setmetatable(state, {
    -- plain `assert(value, message)` like the Lua builtin
    __call = function(_, ...)
      local args = { ... }
      if not args[1] then
        error(args[2] or "assertion failed!", 2)
      end
      return ...
    end,
    __index = function(_, key)
      if key == "register" then
        return function(_, _, name, callback, positive_key, negative_key)
          registry[name] = {
            callback = callback,
            positive = positive_key,
            negative = negative_key,
          }
        end
      end
      if negations[key] then
        return new_state(registry, not positive)
      end
      local entry = registry[key]
      if not entry then
        error("ntf.assert: unknown assertion or modifier: " .. tostring(key), 2)
      end
      return function(...)
        return run(entry, ...)
      end
    end,
  })
end

local function builtin(registry, name, callback)
  registry[name] = {
    callback = callback,
    positive = "ntf.assertion." .. name .. ".positive",
    negative = "ntf.assertion." .. name .. ".negative",
  }
end

local function set_messages(name, positive, negative)
  message:set("ntf.assertion." .. name .. ".positive", positive)
  message:set("ntf.assertion." .. name .. ".negative", negative)
end

local function register_builtins(registry)
  builtin(registry, "equal", function(_, args)
    local a, b = args[1], args[2]
    set_messages(
      "equal",
      ("expected to be equal.\nleft : %s\nright: %s"):format(vim.inspect(a), vim.inspect(b)),
      ("expected to be not equal, but both are: %s"):format(vim.inspect(a))
    )
    return a == b
  end)

  builtin(registry, "same", function(_, args)
    local a, b = args[1], args[2]
    set_messages(
      "same",
      ("expected to be the same.\nleft : %s\nright: %s"):format(vim.inspect(a), vim.inspect(b)),
      ("expected to be not the same, but both are: %s"):format(vim.inspect(a))
    )
    return vim.deep_equal(a, b)
  end)

  builtin(registry, "truthy", function(_, args)
    set_messages(
      "truthy",
      ("expected a truthy value, but got: %s"):format(vim.inspect(args[1])),
      ("expected a falsy value, but got: %s"):format(vim.inspect(args[1]))
    )
    return args[1] ~= nil and args[1] ~= false
  end)
  registry.falsy = {
    callback = function(_, args)
      set_messages(
        "falsy",
        ("expected a falsy value, but got: %s"):format(vim.inspect(args[1])),
        ("expected a truthy value, but got: %s"):format(vim.inspect(args[1]))
      )
      return args[1] == nil or args[1] == false
    end,
    positive = "ntf.assertion.falsy.positive",
    negative = "ntf.assertion.falsy.negative",
  }

  builtin(registry, "is_true", function(_, args)
    set_messages(
      "is_true",
      ("expected true, but got: %s"):format(vim.inspect(args[1])),
      "expected not true, but got true"
    )
    return args[1] == true
  end)

  builtin(registry, "is_false", function(_, args)
    set_messages(
      "is_false",
      ("expected false, but got: %s"):format(vim.inspect(args[1])),
      "expected not false, but got false"
    )
    return args[1] == false
  end)

  builtin(registry, "is_nil", function(_, args)
    set_messages("is_nil", ("expected nil, but got: %s"):format(vim.inspect(args[1])), "expected not nil, but got nil")
    return args[1] == nil
  end)

  builtin(registry, "match", function(_, args)
    local pattern, s = args[1], args[2]
    set_messages(
      "match",
      ("expected to match pattern %q, but got: %s"):format(tostring(pattern), vim.inspect(s)),
      ("expected not to match pattern %q, but got: %s"):format(tostring(pattern), vim.inspect(s))
    )
    return type(s) == "string" and s:find(pattern) ~= nil
  end)
end

--- Create a fresh assert object with its own registry.
--- The returned object is a metatable-driven DSL (`assert.equal`, `assert.no.X`,
--- `:register`), so it is intentionally typed as a plain `table`.
--- @return table
function M.new()
  local registry = {}
  register_builtins(registry)
  return new_state(registry, true)
end

-- Shared singleton used as the global `assert` during a test run and the target
-- of `ntf.assert` registrations.
M.assert = M.new()

return M
