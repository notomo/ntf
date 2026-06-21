local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local schedule = require("ntf.core.schedule")

local function leaf(id, name, isolate, timeout)
  return { type = "it", id = id, name = name, isolate = isolate or false, timeout = timeout }
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

  it("carries an it-level timeout onto its own item at it granularity", function()
    local tree = {
      type = "root",
      id = "",
      children = {
        {
          type = "describe",
          id = "1",
          name = "A",
          isolate = false,
          children = { leaf("1.1", "a1", false, 1000), leaf("1.2", "a2") },
        },
      },
    }

    local items = schedule.split(tree, "it")

    assert.equal(1000, items[1].timeout)
    assert.equal(nil, items[2].timeout)
  end)

  it("takes the unit node's timeout, ignoring inner timeouts when leaves share a process", function()
    local tree = {
      type = "root",
      id = "",
      children = {
        {
          type = "describe",
          id = "1",
          name = "A",
          isolate = false,
          timeout = 5000,
          children = { leaf("1.1", "a1", false, 1000), leaf("1.2", "a2") },
        },
      },
    }

    -- describe granularity: the whole describe is the unit, so its timeout wins
    -- and the inner it timeout (1000) does not produce a separate bound.
    local items = schedule.split(tree, "describe")
    assert.equal(1, #items)
    assert.same({ "1.1", "1.2" }, items[1].node_ids)
    assert.equal(5000, items[1].timeout)
  end)

  it("uses the outermost isolate node's timeout regardless of granularity", function()
    local tree = {
      type = "root",
      id = "",
      children = {
        {
          type = "describe",
          id = "1",
          name = "A",
          isolate = true,
          timeout = 7000,
          children = { leaf("1.1", "a1", false, 1000) },
        },
      },
    }

    local items = schedule.split(tree, "it")

    assert.equal(1, #items)
    assert.equal(7000, items[1].timeout)
  end)
end)
