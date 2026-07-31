local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local baseline = require("ntf.core.mutation.baseline")

--- @param overrides table?
--- @return table
local function entry(overrides)
  return vim.tbl_extend("force", {
    path = "lua/mod.lua",
    col = 7,
    operator = "swap-relational",
    original = "<",
    replacement = "<=",
    line = "  if a < b then",
    rationale = "min(1, 2) is 1 either way",
  }, overrides or {})
end

--- @param overrides table?
--- @return table
local function site(overrides)
  return vim.tbl_extend("force", {
    col = 7,
    operator = "swap-relational",
    original = "<",
    replacement = "<=",
  }, overrides or {})
end

describe("ntf.core.mutation.baseline.validate", function()
  it("accepts an entry", function()
    assert.is_nil(baseline.validate(entry()))
  end)

  it("accepts the optional invariant_spec", function()
    assert.is_nil(baseline.validate(entry({ invariant_spec = "mod keeps a and b apart" })))
  end)

  it("rejects an entry that lacks a field", function()
    local incomplete = entry()
    incomplete.line = nil

    assert.match("needs a string line", baseline.validate(incomplete))
  end)

  it("rejects an invariant_spec that is not a string", function()
    assert.match("needs a non%-empty string invariant_spec", baseline.validate(entry({ invariant_spec = 7 })))
  end)

  it("rejects a blank invariant_spec", function()
    assert.match("needs a non%-empty string invariant_spec", baseline.validate(entry({ invariant_spec = " " })))
  end)

  it("rejects a blank rationale", function()
    assert.match("needs a non%-empty rationale", baseline.validate(entry({ rationale = " " })))
  end)

  it("rejects an entry that is not an object", function()
    assert.match("is not an object", baseline.validate("nope"))
  end)

  it("rejects a non-number col", function()
    assert.match("needs a number col", baseline.validate(entry({ col = "seven" })))
  end)
end)

describe("ntf.core.mutation.baseline.unpinned", function()
  it("reports an entry whose invariant_spec matches no test of the run", function()
    local entries = { entry({ invariant_spec = "mod keeps a and b apart" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "passed" } })

    assert.equal(1, #unpinned)
    assert.equal("mod keeps a and b apart", unpinned[1].invariant_spec)
  end)

  it("keeps an entry whose invariant_spec passed", function()
    local entries = { entry({ invariant_spec = "mod takes the min" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "passed" } })

    assert.equal(0, #unpinned)
  end)

  it("reports an entry whose invariant_spec only went pending, since a pending test asserts nothing", function()
    local entries = { entry({ invariant_spec = "mod takes the min" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "pending" } })

    assert.equal(1, #unpinned)
  end)

  it("leaves an entry carrying no invariant_spec alone", function()
    local unpinned = baseline.unpinned({ entry() }, {})

    assert.equal(0, #unpinned)
  end)
end)

describe("ntf.core.mutation.baseline.matcher", function()
  it("matches a mutant with the same content key", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site()) ~= nil)
    assert.equal(0, #matcher.lost())
  end)

  it("does not match when the line text differs", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_nil(matcher.match("lua/mod.lua", "  if a < c then", site()))
    assert.equal(1, #matcher.lost())
  end)

  it("does not match another column on the same line", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_nil(matcher.match("lua/mod.lua", "  if a < b then", site({ col = 3 })))
  end)

  it("marks every mutant sharing the key, on duplicated lines", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site()) ~= nil)
    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site()) ~= nil)
    assert.equal(0, #matcher.lost())
  end)
end)
