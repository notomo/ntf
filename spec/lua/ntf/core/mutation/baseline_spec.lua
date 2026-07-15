local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local baseline = require("ntf.core.mutation.baseline")
local helper = require("ntf.test.helper")

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

describe("ntf.core.mutation.baseline.load", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("loads the entries", function()
    local file = helper.test_data:create_file("baseline.json", vim.json.encode({ version = 1, entries = { entry() } }))

    local loaded = assert(baseline.load(file))

    assert.equal(1, #loaded)
    assert.equal("lua/mod.lua", loaded[1].path)
    assert.equal(7, loaded[1].col)
  end)

  it("rejects a file that is not JSON", function()
    local file = helper.test_data:create_file("baseline.json", "not json")

    assert.match("invalid JSON", baseline.load(file))
  end)

  it("rejects an unsupported version", function()
    local file = helper.test_data:create_file("baseline.json", vim.json.encode({ version = 2, entries = {} }))

    assert.match("expected version 1", baseline.load(file))
  end)

  it("rejects an entry that lacks a field", function()
    local incomplete = entry()
    incomplete.line = nil
    local file =
      helper.test_data:create_file("baseline.json", vim.json.encode({ version = 1, entries = { incomplete } }))

    assert.match("entries%[1%] needs a string line", baseline.load(file))
  end)

  it("rejects a blank rationale", function()
    local file = helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({ version = 1, entries = { entry({ rationale = " " }) } })
    )

    assert.match("entries%[1%] needs a non%-empty rationale", baseline.load(file))
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
