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
    row = 3,
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

  it("accepts the optional row", function()
    assert.is_nil(baseline.validate(entry({ row = 3 })))
  end)

  it("accepts a row on the first line", function()
    assert.is_nil(baseline.validate(entry({ row = 1 })))
  end)

  it("rejects a row below the first line", function()
    assert.equal("needs a row of 1 or more, or none at all", baseline.validate(entry({ row = 0 })))
  end)

  it("rejects a row that is not a number", function()
    assert.equal("needs a row of 1 or more, or none at all", baseline.validate(entry({ row = "3" })))
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

  it("accepts the optional uncovered", function()
    assert.is_nil(baseline.validate(entry({ uncovered = true })))
  end)

  it("rejects an uncovered that is not true, which would claim coverage the field cannot say", function()
    assert.match("needs an uncovered of true", baseline.validate(entry({ uncovered = false })))
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

  it("accepts the leftmost column a run holds, which is 0 there", function()
    assert.is_nil(baseline.validate(entry({ col = 0 })))
  end)
end)

describe("ntf.core.mutation.baseline.validate_document", function()
  it("accepts an entry", function()
    assert.is_nil(baseline.validate_document(entry()))
  end)

  it("accepts a col on the first column, which a document spells 1", function()
    assert.is_nil(baseline.validate_document(entry({ col = 1 })))
  end)

  it("rejects a col below the first column, rather than leaving it to be reported lost", function()
    assert.equal("needs a col of 1 or more", baseline.validate_document(entry({ col = 0 })))
  end)

  it("rejects what the run form rejects too", function()
    assert.match("needs a number col", baseline.validate_document(entry({ col = "seven" })))
  end)
end)

describe("ntf.core.mutation.baseline.twinned", function()
  local function twin_site(overrides)
    return vim.tbl_extend("force", {
      row = 1,
      col = 7,
      operator = "swap-relational",
      original = "<",
      replacement = "<=",
    }, overrides or {})
  end

  it("reports a site another one shares its whole content with", function()
    local first, second = twin_site(), twin_site({ row = 2 })
    local lines = { "  if a < b then", "  if a < b then" }

    assert.is_true(baseline.twinned({ first, second }, lines, first))
    assert.is_true(baseline.twinned({ first, second }, lines, second))
  end)

  it("leaves a site alone when the other line reads differently", function()
    local first, second = twin_site(), twin_site({ row = 2 })
    local lines = { "  if a < b then", "  if a < c then" }

    assert.is_false(baseline.twinned({ first, second }, lines, first))
  end)

  it("leaves a site alone when the other one sits at another column", function()
    local first, second = twin_site(), twin_site({ row = 2, col = 9 })
    local lines = { "  if a < b then", "  if a < b then" }

    assert.is_false(baseline.twinned({ first, second }, lines, first))
  end)

  it("leaves a site alone when the other one puts something else in place", function()
    local first, second = twin_site(), twin_site({ row = 2, replacement = ">" })
    local lines = { "  if a < b then", "  if a < b then" }

    assert.is_false(baseline.twinned({ first, second }, lines, first))
  end)

  it("leaves the only site of a file alone", function()
    local only = twin_site()

    assert.is_false(baseline.twinned({ only }, { "  if a < b then" }, only))
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
      col = 7,
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

  local TWINNED_MODULE = table.concat({
    "local M = {}",
    "function M.min(a, b)",
    "  if a < b then",
    "    return a",
    "  end",
    "  return b",
    "end",
    "function M.lesser(a, b)",
    "  if a < b then",
    "    return a",
    "  end",
    "  return b",
    "end",
    "return M",
  }, "\n")

  it("carries no row for a position the file holds once", function()
    local cwd = project()

    local built = baseline.build(request(), cwd)

    assert.is_nil(built.row)
  end)

  it("carries the row for a position whose content names a second mutant", function()
    helper.test_data:create_file("lua/mod.lua", TWINNED_MODULE)
    helper.test_data:cd("")

    local built = baseline.build(request({ row = 9 }), helper.test_data.full_path)

    assert.equal(9, built.row)
    assert.equal("  if a < b then", built.line)
  end)

  it("writes the mutant the position holds as an entry", function()
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

  it("closes the file it read the source from", function()
    local cwd = project()
    local module = vim.fs.normalize(helper.test_data:path("lua/mod.lua"))

    assert.is_false(helper.leaves_file_open(module, function()
      baseline.build(request(), cwd)
    end))
  end)

  it("carries the invariant_spec into the entry", function()
    local cwd = project()

    local built = baseline.build(request({ invariant_spec = "mod takes the min" }), cwd)

    assert.equal("mod takes the min", built.invariant_spec)
  end)

  it("carries the uncovered into the entry", function()
    local cwd = project()

    local built = baseline.build(request({ uncovered = true }), cwd)

    assert.is_true(built.uncovered)
  end)

  it("leaves an entry no uncovered where the request makes no such claim", function()
    local cwd = project()

    local built = baseline.build(request(), cwd)

    assert.is_nil(built.uncovered)
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

  it("rejects a position holding no mutant of the operator, listing what the row does hold", function()
    local cwd = project()

    local err = baseline.build(request({ operator = "perturb-number" }), cwd)

    assert.match("lua/mod%.lua:3:8:perturb%-number names no mutant", err)
    assert.match("\n  lua/mod%.lua:3:8:swap%-relational < %-> <=", err)
  end)

  it("lists nothing for a row holding no mutant at all", function()
    local cwd = project()

    local err = baseline.build(request({ row = 1 }), cwd)

    assert.equal("lua/mod.lua:1:8:swap-relational names no mutant", err)
  end)

  it("takes the mutant the col names out of the several a row holds", function()
    local cwd = project()

    local built = baseline.build(request({ row = 9, col = 21 }), cwd)

    assert.equal(21, built.col)
    assert.equal("  return a < b and c < d", built.line)
  end)

  it("rejects a position holding several mutants, listing them with the replacement to take one by", function()
    local cwd = project()

    local err = baseline.build(request({ col = 5, operator = "force-branch" }), cwd)

    assert.match("lua/mod%.lua:3:6:force%-branch names 2 mutants; take one with %-%-replacement", err)
    assert.match(
      "\n  lua/mod%.lua:3:6:force%-branch a < b %-> false\n  lua/mod%.lua:3:6:force%-branch a < b %-> true",
      err
    )
  end)

  it("takes the mutant the replacement names out of the several a position holds", function()
    local cwd = project()

    local built = baseline.build(request({ col = 5, operator = "force-branch", replacement = "true" }), cwd)

    assert.equal("true", built.replacement)
    assert.equal("a < b", built.original)
  end)

  it("rejects a replacement no mutant at the position puts in, listing the ones it does", function()
    local cwd = project()

    local err = baseline.build(request({ col = 5, operator = "force-branch", replacement = "nil" }), cwd)

    assert.match("lua/mod%.lua:3:6:force%-branch puts nothing like nil in place of the original", err)
    assert.match("\n  lua/mod%.lua:3:6:force%-branch a < b %-> false", err)
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

    assert.equal("already in the baseline: lua/mod.lua swap-relational < -> <=", err)
  end)

  it("adds an entry that differs from one on the same line only by its column", function()
    local entries = { entry() }

    local added = baseline.insert(entries, entry({ col = 9 }))

    assert.equal(2, #added)
  end)

  it("adds an entry sharing a position with one that names another row", function()
    local entries = { entry({ row = 3 }) }

    local added = baseline.insert(entries, entry({ row = 9 }))

    assert.equal(2, #added)
    assert.equal(9, added[2].row)
  end)

  it("rejects an entry the baseline already carries at the same row", function()
    local entries = { entry({ row = 3 }) }

    local err = baseline.insert(entries, entry({ row = 3, rationale = "a second opinion" }))

    assert.equal("already in the baseline: lua/mod.lua swap-relational < -> <=", err)
  end)

  it("rejects a row for a position whose entry carries none, which no run could pair up", function()
    local entries = { entry() }

    local err = baseline.insert(entries, entry({ row = 9 }))

    assert.equal(
      "the position already has an entry with no row: lua/mod.lua swap-relational < -> <=; give that one its row first",
      err
    )
  end)

  it("rejects an entry with no row for a position whose entry carries one", function()
    local entries = { entry({ row = 3 }) }

    local err = baseline.insert(entries, entry())

    assert.match("the position already has an entry with no row", err)
  end)
end)

describe("ntf.core.mutation.baseline.unpinned", function()
  it("reports an entry whose invariant_spec matches no test of the run", function()
    local entries = { entry({ invariant_spec = "mod keeps a and b apart" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "passed" } }, true)

    assert.equal(1, #unpinned)
    assert.equal("mod keeps a and b apart", unpinned[1].invariant_spec)
  end)

  it("keeps an entry whose invariant_spec passed", function()
    local entries = { entry({ invariant_spec = "mod takes the min" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "passed" } }, true)

    assert.equal(0, #unpinned)
  end)

  it("reports an entry whose invariant_spec only went pending, since a pending test asserts nothing", function()
    local entries = { entry({ invariant_spec = "mod takes the min" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "pending" } }, true)

    assert.equal(1, #unpinned)
  end)

  it("leaves an entry carrying no invariant_spec alone", function()
    local unpinned = baseline.unpinned({ entry() }, {}, true)

    assert.equal(0, #unpinned)
  end)

  it("leaves every entry alone where the run took part of the suite", function()
    local entries = { entry({ invariant_spec = "mod keeps a and b apart" }) }

    local unpinned = baseline.unpinned(entries, { { names = { "mod", "takes the min" }, status = "passed" } }, false)

    assert.equal(0, #unpinned)
  end)
end)

describe("ntf.core.mutation.baseline.claims", function()
  it("reports an entry no test reaches, which carries no uncovered to say so", function()
    local claims = baseline.claims()

    claims.record(entry(), false)

    assert.equal(1, #claims.uncovered())
    assert.equal(0, #claims.covered())
    assert.equal(0, claims.acknowledged())
  end)

  it("leaves an entry a test reaches alone", function()
    local claims = baseline.claims()

    claims.record(entry(), true)

    assert.equal(0, #claims.uncovered())
    assert.equal(0, #claims.covered())
  end)

  it("stands behind an uncovered entry no test reaches", function()
    local claims = baseline.claims()

    claims.record(entry({ uncovered = true }), false)

    assert.equal(1, claims.acknowledged())
    assert.equal(0, #claims.uncovered())
    assert.equal(0, #claims.covered())
  end)

  it("reports an uncovered entry a test does reach", function()
    local claims = baseline.claims()

    claims.record(entry({ uncovered = true }), true)

    assert.equal(1, #claims.covered())
    assert.equal(0, claims.acknowledged())
  end)

  it("takes one entry once, however many mutants its content named", function()
    local claims = baseline.claims()
    local recorded = entry()

    claims.record(recorded, false)
    claims.record(recorded, false)

    assert.equal(1, #claims.uncovered())
  end)
end)

describe("ntf.core.mutation.baseline.matcher", function()
  local judged = { ["lua/mod.lua"] = true }

  it("matches a mutant with the same content key", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site()) ~= nil)
    assert.equal(0, #matcher.lost(judged))
  end)

  it("does not match when the line text differs", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_nil(matcher.match("lua/mod.lua", "  if a < c then", site()))
    assert.equal(1, #matcher.lost(judged))
  end)

  it("does not match another column on the same line", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_nil(matcher.match("lua/mod.lua", "  if a < b then", site({ col = 3 })))
  end)

  it("marks every mutant sharing the key, on duplicated lines", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site()) ~= nil)
    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site()) ~= nil)
    assert.equal(0, #matcher.lost(judged))
  end)

  it("leaves an entry alone whose file the run never enumerated, as --target narrows it away", function()
    local matcher = baseline.matcher({ entry() })

    assert.equal(0, #matcher.lost({ ["lua/other.lua"] = true }))
    assert.equal(1, #matcher.lost(judged))
  end)

  it("takes no row into account while every entry of the position carries none", function()
    local matcher = baseline.matcher({ entry() })

    assert.is_true(matcher.match("lua/mod.lua", "  if a < b then", site({ row = 99 })) ~= nil)
  end)

  it("gives each mutant the entry naming its own row", function()
    local third, ninth = entry({ row = 3 }), entry({ row = 9, rationale = "the other one" })
    local matcher = baseline.matcher({ third, ninth })

    assert.equal(third, matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 })))
    assert.equal(ninth, matcher.match("lua/mod.lua", "  if a < b then", site({ row = 9 })))
    assert.equal(0, #matcher.lost(judged))
  end)

  it("matches no mutant on a row the position's entries do not name", function()
    local matcher = baseline.matcher({ entry({ row = 3 }) })

    assert.is_nil(matcher.match("lua/mod.lua", "  if a < b then", site({ row = 9 })))
    assert.equal(1, #matcher.lost(judged))
  end)
end)

describe("ntf.core.mutation.baseline.matcher ambiguity", function()
  it("reports a position whose content named two mutants for one entry", function()
    local matcher = baseline.matcher({ entry() })
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 }))
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 9 }))

    local ambiguous = matcher.ambiguous()

    assert.equal(1, #ambiguous)
    assert.equal("lua/mod.lua", ambiguous[1].entry.path)
    assert.same({ 3, 9 }, ambiguous[1].rows)
  end)

  it("reports a position two entries share with no row between them", function()
    local matcher = baseline.matcher({ entry(), entry({ rationale = "the other one" }) })
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 }))

    assert.equal(1, #matcher.ambiguous())
  end)

  it("reports a position only one of whose entries carries a row", function()
    local matcher = baseline.matcher({ entry({ row = 3 }), entry({ rationale = "the other one" }) })
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 }))

    assert.equal(1, #matcher.ambiguous())
  end)

  it("reports a position once, however many mutants its content named", function()
    local matcher = baseline.matcher({ entry(), entry({ rationale = "the other one" }) })
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 }))
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 9 }))

    assert.equal(1, #matcher.ambiguous())
  end)

  it("leaves a position alone whose entries each name a row", function()
    local matcher = baseline.matcher({ entry({ row = 3 }), entry({ row = 9, rationale = "the other one" }) })
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 }))
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 9 }))

    assert.same({}, matcher.ambiguous())
  end)

  it("leaves a lone entry alone whose content named the one mutant", function()
    local matcher = baseline.matcher({ entry() })
    matcher.match("lua/mod.lua", "  if a < b then", site({ row = 3 }))

    assert.same({}, matcher.ambiguous())
  end)

  it("leaves a lone entry alone that the run never reached", function()
    local matcher = baseline.matcher({ entry() })

    assert.same({}, matcher.ambiguous())
  end)
end)
