-- `ntf.assert` is the replacement for `vusted.assert`: it exposes the
-- `register` / `register_eq` / `register_same` surface so that `assertlib` and
-- per-plugin test helpers can register custom assertions onto ntf's own assert
-- object.
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

function M.register(name, fn)
  Assert.create(name):register(fn)
end

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
