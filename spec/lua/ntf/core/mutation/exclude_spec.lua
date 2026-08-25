local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local exclude = require("ntf.core.mutation.exclude")

--- @param overrides table?
--- @return table
local function entry(overrides)
  return vim.tbl_extend("force", {
    path = "lua/mod",
    operators = "all",
    rationale = "every mutant of it runs in a process no spec drives",
  }, overrides or {})
end

--- @param overrides table?
--- @return table
local function spec_entry(overrides)
  local without_operators = entry(overrides)
  without_operators.operators = nil
  return without_operators
end

describe("ntf.core.mutation.exclude.validate", function()
  it("accepts an entry leaving the whole file out", function()
    assert.is_nil(exclude.validate(entry()))
  end)

  it("accepts an entry naming the operators it leaves out", function()
    assert.is_nil(exclude.validate(entry({ operators = { "swap-boolean", "perturb-number" } })))
  end)

  it("rejects an entry that lacks a field", function()
    local incomplete = entry()
    incomplete.path = nil

    assert.match("needs a string path", exclude.validate(incomplete))
  end)

  it("rejects a blank rationale", function()
    assert.match("needs a non%-empty rationale", exclude.validate(entry({ rationale = " " })))
  end)

  it("rejects an entry that is not an object", function()
    assert.match("is not an object", exclude.validate("nope"))
  end)

  it("rejects an entry that names no operators, so the whole file is never the default", function()
    assert.match('needs an operators of "all"', exclude.validate(spec_entry()))
  end)

  it("rejects an empty operators, which would leave nothing out", function()
    assert.match('needs an operators of "all"', exclude.validate(entry({ operators = {} })))
  end)

  it("rejects an operators that is neither the string nor an array", function()
    assert.match('needs an operators of "all"', exclude.validate(entry({ operators = "swap-boolean" })))
  end)

  it("rejects an operator no run produces", function()
    assert.match(
      'names an operator no run produces: "swap%-bool"',
      exclude.validate(entry({
        operators = { "swap-boolean", "swap-bool" },
      }))
    )
  end)
end)

describe("ntf.core.mutation.exclude.validate_spec", function()
  it("accepts an entry", function()
    assert.is_nil(exclude.validate_spec(spec_entry()))
  end)

  it("rejects a blank rationale", function()
    assert.match("needs a non%-empty rationale", exclude.validate_spec(spec_entry({ rationale = " " })))
  end)

  it("rejects an entry naming operators, which decide nothing about a spec", function()
    assert.match("takes no operators", exclude.validate_spec(entry()))
  end)
end)

describe("ntf.core.mutation.exclude.partition", function()
  local cwd = "/project"

  it("drops the files a directory entry covers, keeping the rest in order", function()
    local files = { "/project/lua/a.lua", "/project/lua/sub/b.lua", "/project/other/c.lua" }

    local kept, unused = exclude.partition(files, { entry({ path = "lua" }) }, cwd)

    assert.same({ "/project/other/c.lua" }, kept)
    assert.same({}, unused)
  end)

  it("drops the one file a file entry names", function()
    local files = { "/project/lua/a.lua", "/project/lua/ab.lua" }

    local kept = exclude.partition(files, { entry({ path = "lua/a.lua" }) }, cwd)

    assert.same({ "/project/lua/ab.lua" }, kept)
  end)

  it("keeps a sibling whose name merely starts with a directory entry", function()
    local files = { "/project/luax/a.lua" }

    local kept, unused = exclude.partition(files, { entry({ path = "lua" }) }, cwd)

    assert.same({ "/project/luax/a.lua" }, kept)
    assert.equal(1, #unused)
  end)

  it("reports an entry covering no file", function()
    local files = { "/project/lua/a.lua" }

    local _, unused = exclude.partition(files, { entry({ path = "gone" }) }, cwd)

    assert.equal(1, #unused)
    assert.equal("gone", unused[1].path)
  end)

  it("reports an entry a broader one already covers, whatever their order", function()
    local files = { "/project/lua/a.lua" }
    local narrow, broad = entry({ path = "lua/a.lua" }), entry({ path = "lua" })

    local _, broad_first = exclude.partition(files, { broad, narrow }, cwd)
    local _, narrow_first = exclude.partition(files, { narrow, broad }, cwd)

    assert.same({}, broad_first)
    assert.same({}, narrow_first)
  end)

  it("keeps a file an entry only names operators of, counting the entry as used", function()
    local files = { "/project/lua/a.lua" }

    local kept, unused = exclude.partition(files, { entry({ path = "lua", operators = { "swap-boolean" } }) }, cwd)

    assert.same(files, kept)
    assert.same({}, unused)
  end)

  it("drops the file an exclude_spec entry names, which carries no operators", function()
    local files = { "/project/spec/a_spec.lua" }

    local kept, unused = exclude.partition(files, { spec_entry({ path = "spec/a_spec.lua" }) }, cwd)

    assert.same({}, kept)
    assert.same({}, unused)
  end)

  it("keeps every file when no entry is given", function()
    local files = { "/project/lua/a.lua" }

    local kept, unused = exclude.partition(files, {}, cwd)

    assert.same(files, kept)
    assert.same({}, unused)
  end)

  it("normalizes an entry path that carries a trailing slash", function()
    local files = { "/project/lua/a.lua" }

    local kept, unused = exclude.partition(files, { entry({ path = "lua/" }) }, cwd)

    assert.same({}, kept)
    assert.same({}, unused)
  end)
end)

describe("ntf.core.mutation.exclude.within", function()
  local cwd = "/project"

  it("keeps an entry a spec path of the run holds", function()
    local entries = { spec_entry({ path = "spec/a_spec.lua" }) }

    local kept = exclude.within(entries, { "/project/spec" }, cwd)

    assert.equal(1, #kept)
    assert.equal("spec/a_spec.lua", kept[1].path)
  end)

  it("keeps an entry a spec path of the run names outright", function()
    local entries = { spec_entry({ path = "spec/a_spec.lua" }) }

    local kept = exclude.within(entries, { "/project/spec/a_spec.lua" }, cwd)

    assert.equal(1, #kept)
  end)

  it("drops an entry no spec path of the run holds, which never looked for the file it names", function()
    local entries = { spec_entry({ path = "spec/a_spec.lua" }) }

    local kept = exclude.within(entries, { "/project/spec/b_spec.lua" }, cwd)

    assert.same({}, kept)
  end)

  it("drops an entry a spec path merely shares its first characters with", function()
    local entries = { spec_entry({ path = "specs/a_spec.lua" }) }

    local kept = exclude.within(entries, { "/project/spec" }, cwd)

    assert.same({}, kept)
  end)

  it("keeps an entry held by the second of the run's spec paths", function()
    local entries = { spec_entry({ path = "spec/a_spec.lua" }) }

    local kept = exclude.within(entries, { "/project/other", "/project/spec" }, cwd)

    assert.equal(1, #kept)
  end)
end)

describe("ntf.core.mutation.exclude.operator_filter", function()
  local cwd = "/project"

  it("leaves out the operators an entry names, under the path it names", function()
    local excluded = exclude.operator_filter({ entry({ path = "lua", operators = { "swap-boolean" } }) }, cwd)

    assert.is_true(excluded("/project/lua/sub/a.lua", "swap-boolean"))
    assert.is_false(excluded("/project/lua/sub/a.lua", "perturb-number"))
    assert.is_false(excluded("/project/other/a.lua", "swap-boolean"))
  end)

  it("leaves out nothing for an entry covering the whole file, which never reaches a mutant", function()
    local excluded = exclude.operator_filter({ entry({ path = "lua" }) }, cwd)

    assert.is_false(excluded("/project/lua/a.lua", "swap-boolean"))
  end)

  it("leaves out an operator any one of the entries names", function()
    local excluded = exclude.operator_filter({
      entry({ path = "lua", operators = { "swap-boolean" } }),
      entry({ path = "lua/a.lua", operators = { "perturb-number" } }),
    }, cwd)

    assert.is_true(excluded("/project/lua/a.lua", "perturb-number"))
    assert.is_false(excluded("/project/lua/b.lua", "perturb-number"))
  end)

  it("leaves out nothing when no entry is given", function()
    local excluded = exclude.operator_filter({}, cwd)

    assert.is_false(excluded("/project/lua/a.lua", "swap-boolean"))
  end)
end)

describe("ntf.core.mutation.exclude.item_indexes", function()
  local cwd = "/project"

  --- @param file string
  --- @return table
  local function item(file)
    return { file = file, node_id = "1", names = { "test" } }
  end

  it("returns the indexes of every item a directory entry covers", function()
    local items =
      { item("/project/spec/e2e/a_spec.lua"), item("/project/spec/b_spec.lua"), item("/project/spec/e2e/a_spec.lua") }

    local indexes = exclude.item_indexes(items, { spec_entry({ path = "spec/e2e" }) }, cwd)

    assert.same({ [1] = true, [3] = true }, indexes)
  end)

  it("returns no index when no entry is given", function()
    local items = { item("/project/spec/a_spec.lua") }

    assert.same({}, exclude.item_indexes(items, {}, cwd))
  end)

  it("returns no index when the entry covers no item", function()
    local items = { item("/project/spec/a_spec.lua") }

    assert.same({}, exclude.item_indexes(items, { spec_entry({ path = "spec/gone_spec.lua" }) }, cwd))
  end)
end)
