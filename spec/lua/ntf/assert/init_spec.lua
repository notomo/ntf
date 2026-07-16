local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert

describe("ntf.assert", function()
  local function fails(fn)
    local ok = pcall(fn)
    return not ok
  end

  local function failure(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
  end

  it("supports equal / same", function()
    assert.equal(1, 1)
    assert.same({ a = 1, b = { 2 } }, { a = 1, b = { 2 } })
    assert.is_true(fails(function()
      assert.equal(1, 2)
    end))
    assert.is_true(fails(function()
      assert.same({ 1 }, { 2 })
    end))
  end)

  it("supports is_true / is_false / is_nil / truthy / falsy", function()
    assert.is_true(true)
    assert.is_false(false)
    assert.is_nil(nil)
    assert.truthy(1)
    assert.falsy(nil)
    assert.is_true(fails(function()
      assert.is_true(false)
    end))
  end)

  it("truthy accepts everything but nil and false", function()
    assert.truthy(true)
    assert.truthy(0)
    assert.truthy("")
    assert.is_true(fails(function()
      assert.truthy(false)
    end))
    assert.is_true(fails(function()
      assert.truthy(nil)
    end))
  end)

  it("falsy accepts only nil and false", function()
    assert.falsy(false)
    assert.falsy(nil)
    assert.is_true(fails(function()
      assert.falsy(1)
    end))
    assert.is_true(fails(function()
      assert.falsy(0)
    end))
  end)

  it("reports the failing values in the failure message", function()
    assert.match(
      "expected to be equal.\nleft : 1\nright: 2",
      failure(function()
        assert.equal(1, 2)
      end)
    )
    assert.match(
      "expected to be not equal, but both are: 1",
      failure(function()
        assert.no.equal(1, 1)
      end)
    )
  end)

  it("reports the got value for truthy / falsy failures", function()
    assert.match(
      "expected a truthy value, but got: false",
      failure(function()
        assert.truthy(false)
      end)
    )
    assert.match(
      "expected a falsy value, but got: 1",
      failure(function()
        assert.no.truthy(1)
      end)
    )
    assert.match(
      "expected a falsy value, but got: 1",
      failure(function()
        assert.falsy(1)
      end)
    )
    assert.match(
      "expected a truthy value, but got: false",
      failure(function()
        assert.no.falsy(false)
      end)
    )
  end)

  it("reports the got value for is_true / is_false / is_nil failures", function()
    assert.match(
      "expected true, but got: false",
      failure(function()
        assert.is_true(false)
      end)
    )
    assert.match(
      "expected false, but got: true",
      failure(function()
        assert.is_false(true)
      end)
    )
    assert.match(
      "expected nil, but got: 1",
      failure(function()
        assert.is_nil(1)
      end)
    )
  end)

  it("points the failure at the assertion call site", function()
    local function failing()
      assert.equal(1, 2)
    end
    local line = debug.getinfo(failing, "S").linedefined + 1
    assert.match("init_spec%.lua:" .. line .. ": expected to be equal", failure(failing))
  end)

  it("supports match", function()
    assert.match("b.d", "abcd")
    assert.is_true(fails(function()
      assert.match("zzz", "abcd")
    end))
  end)

  it("supports the `no` negation modifier", function()
    assert.no.equal(1, 2)
    assert.no.is_nil(1)
    assert.is_true(fails(function()
      assert.no.equal(1, 1)
    end))
  end)

  it("callable form behaves like the builtin assert", function()
    assert(true)
    assert.is_true(fails(function()
      assert(false, "boom")
    end))
  end)

  it("callable form reports the given message at the caller's line", function()
    local function failing()
      assert(false, "boom")
    end
    local line = debug.getinfo(failing, "S").linedefined + 1
    assert.match("init_spec%.lua:" .. line .. ": boom$", failure(failing))
  end)

  it("can register a custom assertion via ntf.assert.register", function()
    require("ntf.assert").register("even", function(self)
      self:set_positive("should be even")
      self:set_negative("should not be even")
      return function(_, args)
        return args[1] % 2 == 0
      end
    end)
    assert.even(2)
    assert.no.even(3)
    assert.is_true(fails(function()
      assert.even(3)
    end))
  end)

  it("registers custom asserts through ntf.assert (assertlib path)", function()
    -- the surface per-plugin helpers use: register_eq(name, fn)
    require("ntf.assert").register_eq("spec_double", function(n)
      return n * 2
    end)
    assert.spec_double(3, 6)
    assert.no.spec_double(3, 7)
    assert.is_true(fails(function()
      assert.spec_double(3, 7)
    end))
  end)

  it("register_eq hands only the leading args to get_actual", function()
    require("ntf.assert").register_eq("spec_arg_count", function(...)
      return select("#", ...)
    end)
    assert.spec_arg_count("a", "b", 2)
  end)

  it("register_same hands only the leading args to get_actual", function()
    require("ntf.assert").register_same("spec_arg_count_same", function(...)
      return { count = select("#", ...) }
    end)
    assert.spec_arg_count_same("a", "b", { count = 2 })
  end)

  it("registers deep-equality asserts via ntf.assert.register_same", function()
    require("ntf.assert").register_same("spec_wrap", function(n)
      return { value = n }
    end)
    assert.spec_wrap(3, { value = 3 })
    assert.no.spec_wrap(3, { value = 4 })
    assert.is_true(fails(function()
      assert.spec_wrap(3, { value = 4 })
    end))
  end)
end)
