local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local stats = require("ntf.core.coverage.stats")
local helper = require("ntf.test.helper")

local function read_all(path)
  local f = assert(io.open(path, "r"))
  local content = f:read("*a")
  f:close()
  return content
end

describe("ntf.core.coverage.stats.write", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("writes the luacov.stats.out format (header line + space-separated counts)", function()
    local out = helper.test_data:path("luacov.stats.out")
    stats.write(out, { ["/x.lua"] = { max = 3, lines = { [1] = 2, [3] = 5 } } })

    -- "<max>:<path>" then counts for lines 1..max, unhit lines written as 0.
    assert.equal("3:/x.lua\n2 0 5\n", read_all(out))
  end)

  it("emits one block per file, sorted by path", function()
    local out = helper.test_data:path("luacov.stats.out")
    stats.write(out, {
      ["/b.lua"] = { max = 1, lines = { [1] = 1 } },
      ["/a.lua"] = { max = 2, lines = { [2] = 4 } },
    })

    assert.equal("2:/a.lua\n0 4\n1:/b.lua\n1\n", read_all(out))
  end)

  it("writes an empty file when nothing was measured", function()
    local out = helper.test_data:path("luacov.stats.out")
    stats.write(out, {})

    assert.equal("", read_all(out))
  end)
end)

describe("ntf.core.coverage.stats.read", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("parses a header + counts block into { max, lines } with integer keys", function()
    local out = helper.test_data:create_file("luacov.stats.out", "3:/x.lua\n2 0 5\n")

    assert.same({ ["/x.lua"] = { max = 3, lines = { [1] = 2, [2] = 0, [3] = 5 } } }, stats.read(out))
  end)

  it("round-trips write -> read", function()
    local out = helper.test_data:path("luacov.stats.out")
    local merged = {
      ["/a.lua"] = { max = 2, lines = { [1] = 0, [2] = 4 } },
      ["/b.lua"] = { max = 1, lines = { [1] = 1 } },
    }
    stats.write(out, merged)

    assert.same(merged, stats.read(out))
  end)

  it("returns an empty table for a missing file", function()
    assert.same({}, stats.read(helper.test_data:path("nope.stats.out")))
  end)

  it("returns an empty table for an empty file", function()
    local out = helper.test_data:create_file("luacov.stats.out", "")

    assert.same({}, stats.read(out))
  end)
end)
