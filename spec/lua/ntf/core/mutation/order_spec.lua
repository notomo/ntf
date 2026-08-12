local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local order = require("ntf.core.mutation.order")

--- @param ms number
local function task(ms)
  return { trials = { { baseline_ms = ms } } }
end

describe("ntf.core.mutation.order", function()
  it("dispatches the slowest task first", function()
    assert.same({ 2, 3, 1 }, order.order({ task(1), task(3), task(2) }))
  end)

  it("keeps the input order between tasks of the same cost, however the sort shuffles a tie", function()
    assert.same({ 1, 2, 3, 4 }, order.order({ task(5), task(5), task(5), task(5) }))
  end)
end)
