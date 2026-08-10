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

describe("ntf.core.mutation.baseline.build", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  local MODULE = table.concat({
    "local M = {}",
    "function M.min(a, b)",
    "  if a < b then",
    "    return a",
    "  end",
    "  return b",
    "end",
    "function M.both(a, b, c, d)",
    "  return a < b and c < d",
    "end",
    "return M",
  }, "\n")

  --- @param overrides table?
  --- @return table
  local function request(overrides)
    return vim.tbl_extend("force", {
      path = "lua/mod.lua",
      row = 3,
      operator = "swap-relational",
      rationale = "min(1, 2) is 1 either way",
    }, overrides or {})
  end

  --- @return string # working directory the module sits in
  local function project()
    helper.test_data:create_file("lua/mod.lua", MODULE)
    helper.test_data:cd("")
    return helper.test_data.full_path
  end

  it("writes the mutant the row holds as an entry", function()
    local cwd = project()

    local built = baseline.build(request(), cwd)

    assert.same({
      path = "lua/mod.lua",
      col = 7,
      operator = "swap-relational",
      original = "<",
      replacement = "<=",
      line = "  if a < b then",
      rationale = "min(1, 2) is 1 either way",
    }, built)
  end)

  it("carries the invariant_spec into the entry", function()
    local cwd = project()

    local built = baseline.build(request({ invariant_spec = "mod takes the min" }), cwd)

    assert.equal("mod takes the min", built.invariant_spec)
  end)

  it("names the file relative to the working directory, whatever form the request spells", function()
    local cwd = project()

    local built = baseline.build(request({ path = vim.fs.joinpath(cwd, "lua/mod.lua") }), cwd)

    assert.equal("lua/mod.lua", built.path)
  end)

  it("rejects a file outside the working directory, which no entry can name", function()
    local cwd = project()
    local outside = helper.test_data:create_file("outside.lua", MODULE)
    helper.test_data:cd("lua")

    local err = baseline.build(request({ path = outside }), vim.fs.joinpath(cwd, "lua"))

    assert.match("outside the working directory", err)
  end)

  it("rejects a file it cannot read", function()
    local cwd = project()

    local err = baseline.build(request({ path = "lua/missing.lua" }), cwd)

    assert.equal("cannot read lua/missing.lua", err)
  end)

  it("rejects a row holding no mutant of the operator, listing what it does hold", function()
    local cwd = project()

    local err = baseline.build(request({ operator = "perturb-number" }), cwd)

    assert.match("lua/mod%.lua:3 has no perturb%-number mutant", err)
    assert.match("\n  col 7 swap%-relational: < %-> <=", err)
  end)

  it("lists nothing for a row holding no mutant at all", function()
    local cwd = project()

    local err = baseline.build(request({ row = 1 }), cwd)

    assert.equal("lua/mod.lua:1 has no swap-relational mutant", err)
  end)

  it("rejects a row holding several of the operator's mutants, listing them with the column to name one by", function()
    local cwd = project()

    local err = baseline.build(request({ row = 9 }), cwd)

    assert.match("lua/mod%.lua:9 has 2 swap%-relational mutants; name one with %-%-col", err)
    assert.match("\n  col 11 swap%-relational: < %-> <=\n  col 21 swap%-relational: < %-> <=", err)
  end)

  it("takes the mutant the col names out of the several a row holds", function()
    local cwd = project()

    local built = baseline.build(request({ row = 9, col = 21 }), cwd)

    assert.equal(21, built.col)
    assert.equal("  return a < b and c < d", built.line)
  end)

  it("rejects a col holding no mutant of the operator, listing the ones the row does hold", function()
    local cwd = project()

    local err = baseline.build(request({ row = 9, col = 12 }), cwd)

    assert.match("lua/mod%.lua:9 has no swap%-relational mutant at col 12", err)
    assert.match("\n  col 11 swap%-relational: < %-> <=", err)
  end)

  it("holds the built entry to what the config accepts", function()
    local cwd = project()

    local err = baseline.build(request({ rationale = " " }), cwd)

    assert.equal("the entry needs a non-empty rationale", err)
  end)
end)

describe("ntf.core.mutation.baseline.insert", function()
  it("adds an entry to an empty baseline", function()
    local added = baseline.insert({}, entry())

    assert.equal(1, #added)
    assert.equal("lua/mod.lua", added[1].path)
  end)

  it("adds an entry after the last one naming the same file", function()
    local entries = {
      entry({ path = "lua/a.lua" }),
      entry({ path = "lua/mod.lua", col = 1 }),
      entry({ path = "lua/z.lua" }),
    }

    local added = baseline.insert(entries, entry({ col = 9 }))

    assert.same(
      { "lua/a.lua", "lua/mod.lua", "lua/mod.lua", "lua/z.lua" },
      vim.tbl_map(function(e)
        return e.path
      end, added)
    )
    assert.equal(9, added[3].col)
  end)

  it("adds an entry naming a file no entry does at the end", function()
    local entries = { entry({ path = "lua/a.lua" }) }

    local added = baseline.insert(entries, entry())

    assert.equal(2, #added)
    assert.equal("lua/mod.lua", added[2].path)
  end)

  it("leaves the given entries alone", function()
    local entries = { entry({ path = "lua/a.lua" }) }

    baseline.insert(entries, entry())

    assert.equal(1, #entries)
  end)

  it("rejects an entry the baseline already carries", function()
    local entries = { entry() }

    local err = baseline.insert(entries, entry({ rationale = "a second opinion" }))

    assert.equal("already in the baseline: lua/mod.lua swap-relational: < -> <=", err)
  end)

  it("adds an entry that differs from one on the same line only by its column", function()
    local entries = { entry() }

    local added = baseline.insert(entries, entry({ col = 9 }))

    assert.equal(2, #added)
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
