local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local coverage_map = require("ntf.core.mutation.coverage_map")

describe("ntf.core.mutation.coverage_map", function()
  it("returns the items that hit any of the rows", function()
    local map = coverage_map.new()
    map.add(1, { ["/x.lua"] = { max = 3, lines = { ["1"] = 1, ["2"] = 1 } } })
    map.add(2, { ["/x.lua"] = { max = 3, lines = { ["2"] = 1, ["3"] = 1 } } })

    assert.same({ 1 }, map.item_indexes("/x.lua", { 1 }))
    assert.same({ 1, 2 }, map.item_indexes("/x.lua", { 2 }))
    assert.same({ 1, 2 }, map.item_indexes("/x.lua", { 1, 3 }))
  end)

  it("returns no item for an unhit row", function()
    local map = coverage_map.new()
    map.add(1, { ["/x.lua"] = { max = 1, lines = { ["1"] = 1 } } })

    assert.same({}, map.item_indexes("/x.lua", { 2 }))
  end)

  it("returns no item for an unknown path", function()
    local map = coverage_map.new()
    map.add(1, { ["/x.lua"] = { max = 1, lines = { ["1"] = 1 } } })

    assert.same({}, map.item_indexes("/y.lua", { 1 }))
  end)

  it("tolerates a worker that measured nothing", function()
    local map = coverage_map.new()
    map.add(1, nil)

    assert.same({}, map.item_indexes("/x.lua", { 1 }))
  end)
end)
