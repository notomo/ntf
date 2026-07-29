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

  it("loads the optional invariant_spec", function()
    local file = helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({ version = 1, entries = { entry({ invariant_spec = "mod keeps a and b apart" }) } })
    )

    local loaded = assert(baseline.load(file))

    assert.equal("mod keeps a and b apart", loaded[1].invariant_spec)
  end)

  it("rejects an invariant_spec that is not a string", function()
    local file = helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({ version = 1, entries = { entry({ invariant_spec = 7 }) } })
    )

    assert.match("entries%[1%] needs a non%-empty string invariant_spec", baseline.load(file))
  end)

  it("rejects a blank invariant_spec", function()
    local file = helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({ version = 1, entries = { entry({ invariant_spec = " " }) } })
    )

    assert.match("entries%[1%] needs a non%-empty string invariant_spec", baseline.load(file))
  end)

  it("rejects a blank rationale", function()
    local file = helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({ version = 1, entries = { entry({ rationale = " " }) } })
    )

    assert.match("entries%[1%] needs a non%-empty rationale", baseline.load(file))
  end)

  it("rejects an entry that is not an object", function()
    local file = helper.test_data:create_file("baseline.json", vim.json.encode({ version = 1, entries = { "nope" } }))

    assert.match("entries%[1%] is not an object", baseline.load(file))
  end)

  it("rejects a non-number col", function()
    local file = helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({ version = 1, entries = { entry({ col = "seven" }) } })
    )

    assert.match("entries%[1%] needs a number col", baseline.load(file))
  end)

  it("rejects a file that cannot be read", function()
    assert.match("cannot be read", baseline.load(vim.fs.joinpath(helper.test_data.full_path, "missing.json")))
  end)

  it("rejects a document whose entries are not an array", function()
    local file = helper.test_data:create_file("baseline.json", vim.json.encode({ version = 1, entries = "nope" }))

    assert.match("expected an entries array", baseline.load(file))
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
