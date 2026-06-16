local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local tree = require("ntf.core.tree")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending

describe("outer", function()
  it("one", function() end)
  pending("pending two")
  describe("inner", function()
    it("three", function() end)
  end)
  it("isolated four", function() end, { isolate = true })
end)

describe("isolated group", function()
  it("five", function() end)
end, { isolate = true })
]]

describe("ntf.core.tree.build", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("builds nodes with stable index-path ids", function()
    local root = tree.build(helper.write_spec(source))

    local outer = root.children[1]
    assert.equal("outer", outer.name)
    assert.equal("1", outer.id)
    assert.equal("1.1", outer.children[1].id)
    assert.equal("one", outer.children[1].name)
    assert.equal("1.3", outer.children[3].id)
    assert.equal("inner", outer.children[3].name)
    assert.equal("1.3.1", outer.children[3].children[1].id)
  end)

  it("marks explicit pending() as a pending node", function()
    local root = tree.build(helper.write_spec(source))
    local pending_node = root.children[1].children[2]
    assert.equal("pending", pending_node.type)
    assert.equal("pending two", pending_node.name)
  end)

  it("records .isolate opt-in on it and describe", function()
    local root = tree.build(helper.write_spec(source))
    local isolated_it = root.children[1].children[4]
    assert.equal("isolated four", isolated_it.name)
    assert.is_true(isolated_it.isolate)

    local isolated_describe = root.children[2]
    assert.equal("isolated group", isolated_describe.name)
    assert.is_true(isolated_describe.isolate)
  end)

  it("captures load errors instead of throwing", function()
    local root = tree.build(helper.write_spec([[error("intentionally broken")]]))
    assert.truthy(root.load_error)
  end)

  it("surfaces an error thrown inside a describe body as the load error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("outer", function()
  it("one", function() end)
  error("broken describe body")
end)
]]))
    assert.match("broken describe body", tostring(root.load_error))
  end)
end)
