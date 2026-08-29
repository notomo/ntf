local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local budget = require("ntf.core.mutation.budget")

describe("ntf.core.mutation.budget.trial", function()
  it("gives a trial three seconds, however fast the test was in the baseline run", function()
    local instant = 0
    local untimed = 0
    assert.equal(3000, budget.trial(instant, untimed))
  end)

  it("gives a slower test twice its baseline and two seconds more", function()
    assert.equal(8000, budget.trial(3000, 0))
  end)

  it("rounds a fractional baseline down to whole milliseconds", function()
    assert.equal(8001, budget.trial(3000.7, 0))
  end)

  it("caps a trial at the run's own timeout", function()
    assert.equal(4000, budget.trial(3000, 4000))
  end)

  it("caps a trial at a timeout of a single millisecond, the shortest a run can ask for", function()
    assert.equal(1, budget.trial(3000, 1))
  end)

  it("leaves a trial that already fits inside the timeout alone", function()
    assert.equal(8000, budget.trial(3000, 60000))
  end)
end)
