local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local work = require("ntf.core.controller.work")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("math", function()
  it("adds", function() end)
  it("subtracts", function() end)
end)

describe("string", function()
  it("adds", function() end)
end)
]]

local MATH_ADDS, MATH_SUBTRACTS, STRING_ADDS = "1.1", "1.2", "2.1"

local function planned_ids(items)
  return vim.tbl_map(function(item)
    return item.node_id
  end, items)
end

describe("ntf.core.controller.work.plan", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("keeps every leaf when no filter is given", function()
    local file = helper.write_spec(source)
    local items = work.plan({ file })

    assert.same({ MATH_ADDS, MATH_SUBTRACTS, STRING_ADDS }, planned_ids(items))
  end)

  it("keeps only leaves whose full name matches the filter", function()
    local file = helper.write_spec(source)
    local items = work.plan({ file }, "adds")

    assert.same({ MATH_ADDS, STRING_ADDS }, planned_ids(items))
  end)

  it("matches the filter as a Lua pattern against the full name", function()
    local file = helper.write_spec(source)
    local items = work.plan({ file }, "^math")

    assert.same({ MATH_ADDS, MATH_SUBTRACTS }, planned_ids(items))
  end)

  it("drops work items that have no matching leaf", function()
    local file = helper.write_spec(source)
    local items = work.plan({ file }, "subtracts")

    assert.equal(1, #items)
    assert.equal(MATH_SUBTRACTS, items[1].node_id)
  end)

  it("yields no items when the filter matches nothing", function()
    local file = helper.write_spec(source)
    local items = work.plan({ file }, "nope")

    assert.equal(0, #items)
  end)

  it("carries an it-level timeout onto its item", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("A", function()
  it("slow", function() end, { timeout = 1000 })
  it("normal", function() end)
end)
]])
    local items = work.plan({ file })

    assert.equal(1000, items[1].timeout)
    assert.equal(nil, items[2].timeout)
  end)

  it("schedules a describe whose body errored as its own work item", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("broken", function()
  it("never reached", function() end)
  error("describe body blew up")
end)
]])
    local items, load_errors = work.plan({ file })

    local broken_describe = "1"
    assert.same({}, load_errors)
    assert.same({ broken_describe }, planned_ids(items))
  end)
end)
