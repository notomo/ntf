local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local budget = require("ntf.core.controller.budget")

describe("ntf.core.controller.budget.run", function()
  it("keeps the ten-minute floor for a run of few tests", function()
    assert.equal(600000, budget.run(3))
  end)

  it("gives every test ten seconds once they earn more than the floor", function()
    assert.equal(700000, budget.run(70))
  end)
end)
