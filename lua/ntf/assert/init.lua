local assert = require("ntf.assert.builder").assert
local message = require("ntf.assert.message")

local M = {}

local Assert = {}
Assert.__index = Assert

function Assert.create(name)
  local tbl = {
    name = name,
    positive = ("assertion.%s.positive"):format(name),
    negative = ("assertion.%s.negative"):format(name),
  }
  return setmetatable(tbl, Assert)
end

function Assert.set_positive(self, msg)
  message:set(self.positive, msg)
end

function Assert.set_negative(self, msg)
  message:set(self.negative, msg)
end

function Assert.register(self, fn)
  assert:register("assertion", self.name, fn(self), self.positive, self.negative)
end

--- Register a custom assertion onto ntf's assert object.
--- Available afterwards as `assert.{name}(...)` and `assert.is_not.{name}(...)`.
--- @param name string: assertion name
--- @param fn function: factory `function(self) return function(_, args) ... end end` returning the predicate
function M.register(name, fn)
  Assert.create(name):register(fn)
end

--- Register an assertion that compares the actual value with `==`.
--- @param name string: assertion name
--- @param get_actual function: maps the leading args to the actual value (last arg is the expected)
function M.register_eq(name, get_actual)
  local self = Assert.create(name)
  self:register(function(_)
    return function(_, args)
      local expected = args[#args]
      local actual = get_actual(unpack(args, 1, #args - 1))

      local positive_msg = ("%s should be %s, but actual: %s"):format(name, expected, actual)
      self:set_positive(positive_msg)
      local negative_msg = ("%s should not be %s, but actual: %s"):format(name, expected, actual)
      self:set_negative(negative_msg)

      return actual == expected
    end
  end)
end

--- Register an assertion that compares the actual value with deep equality.
--- @param name string: assertion name
--- @param get_actual function: maps the leading args to the actual value (last arg is the expected)
function M.register_same(name, get_actual)
  local self = Assert.create(name)
  self:register(function(_)
    return function(_, args)
      local expected = vim.inspect(args[#args])
      local actual = vim.inspect(get_actual(unpack(args, 1, #args - 1)))

      local positive_msg = ("%s should be %s, but actual: %s"):format(name, expected, actual)
      self:set_positive(positive_msg)
      local negative_msg = ("%s should not be %s, but actual: %s"):format(name, expected, actual)
      self:set_negative(negative_msg)

      return vim.deep_equal(actual, expected)
    end
  end)
end

return M
