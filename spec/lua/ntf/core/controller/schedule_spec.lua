local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local schedule = require("ntf.core.controller.schedule")

local function leaf(id, name, timeout)
  return { type = "it", id = id, name = name, timeout = timeout }
end

-- Two describes; the first holds two leaves, the second holds one.
local function fake_tree()
  return {
    type = "root",
    id = "",
    children = {
      {
        type = "describe",
        id = "1",
        name = "A",
        children = { leaf("1.1", "a1"), leaf("1.2", "a2") },
      },
      {
        type = "describe",
        id = "2",
        name = "B",
        children = { leaf("2.1", "b1") },
      },
    },
  }
end

describe("ntf.core.controller.schedule.split", function()
  it("yields one item per leaf", function()
    local items = schedule.split(fake_tree())
    assert.equal(3, #items)
    assert.same({ "1.1" }, items[1].node_ids)
    assert.same({ "1.2" }, items[2].node_ids)
    assert.same({ "2.1" }, items[3].node_ids)
  end)

  it("carries an it-level timeout onto its item", function()
    local tree = {
      type = "root",
      id = "",
      children = {
        {
          type = "describe",
          id = "1",
          name = "A",
          children = { leaf("1.1", "a1", 1000), leaf("1.2", "a2") },
        },
      },
    }

    local items = schedule.split(tree)

    assert.equal(1000, items[1].timeout)
    assert.equal(nil, items[2].timeout)
  end)
end)
