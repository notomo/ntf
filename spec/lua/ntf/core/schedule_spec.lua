local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local schedule = require("ntf.core.schedule")

local function leaf(id, name, isolate)
  return { type = "it", id = id, name = name, isolate = isolate or false }
end

-- A: two plain leaves; B: one leaf opted into .isolate
local function fake_tree()
  return {
    type = "root",
    id = "",
    children = {
      {
        type = "describe",
        id = "1",
        name = "A",
        isolate = false,
        children = { leaf("1.1", "a1"), leaf("1.2", "a2") },
      },
      {
        type = "describe",
        id = "2",
        name = "B",
        isolate = false,
        children = { leaf("2.1", "b1", true) },
      },
    },
  }
end

describe("ntf.core.schedule.split", function()
  it("file granularity yields one item, but .isolate forces a split", function()
    local items = schedule.split(fake_tree(), "file")
    assert.equal(2, #items)
    assert.same({ "1.1", "1.2" }, items[1].node_ids)
    assert.same({ "2.1" }, items[2].node_ids)
  end)

  it("describe granularity groups by top-level describe", function()
    local items = schedule.split(fake_tree(), "describe")
    assert.equal(2, #items)
    assert.same({ "1.1", "1.2" }, items[1].node_ids)
    assert.same({ "2.1" }, items[2].node_ids)
  end)

  it("it granularity yields one item per leaf", function()
    local items = schedule.split(fake_tree(), "it")
    assert.equal(3, #items)
    assert.same({ "1.1" }, items[1].node_ids)
    assert.same({ "1.2" }, items[2].node_ids)
    assert.same({ "2.1" }, items[3].node_ids)
  end)
end)
