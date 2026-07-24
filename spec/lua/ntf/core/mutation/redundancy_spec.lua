local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local redundancy = require("ntf.core.mutation.redundancy")

--- @param killers string[]?
--- @param killed_by string?
local function record(killers, killed_by)
  killed_by = killed_by or (killers or {})[1]
  return {
    mutant = {
      path = "/x.lua",
      operator = "swap-relational",
      row = 1,
      col = 0,
      end_row = 1,
      end_col = 1,
      start_byte = 0,
      end_byte = 1,
      original = "<",
      replacement = "<=",
    },
    status = killed_by and "killed" or "survived",
    killers = killers,
    killed_by = killed_by,
  }
end

describe("ntf.core.mutation.redundancy.analyze", function()
  it("lists the tests that are never a mutant's only killer, most-detecting first", function()
    local result = redundancy.analyze({
      record({ "sole" }),
      record({ "zz", "aa" }),
      record({ "zz", "mm" }),
      record({ "zz", "aa", "mm" }),
    })

    assert.equal(4, result.mutants)
    assert.same({
      { name = "zz", detected = 3 },
      { name = "aa", detected = 2 },
      { name = "mm", detected = 2 },
    }, result.tests)
  end)

  it("spares a test that is the only killer of even one mutant", function()
    local result = redundancy.analyze({
      record({ "broad", "narrow" }),
      record({ "broad", "narrow" }),
      record({ "narrow" }),
    })

    assert.same({ { name = "broad", detected = 2 } }, result.tests)
  end)

  it("leaves out the mutants whose killer set was never completed", function()
    local result = redundancy.analyze({
      record({ "counted", "sole" }),
      record({ "sole" }),
      record(nil, "counted"),
    })

    assert.equal(2, result.mutants)
    assert.same({ { name = "counted", detected = 1 } }, result.tests)
  end)

  it("reports no mutants when nothing carries a killer set", function()
    local result = redundancy.analyze({ record(nil, "a") })

    assert.equal(0, result.mutants)
    assert.same({}, result.tests)
  end)

  it("counts a survived mutant's empty killer set without naming anyone", function()
    local result = redundancy.analyze({ record({}) })

    assert.equal(1, result.mutants)
    assert.same({}, result.tests)
  end)
end)
