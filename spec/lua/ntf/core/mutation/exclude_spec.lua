local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local exclude = require("ntf.core.mutation.exclude")
local helper = require("ntf.test.helper")

--- @param overrides table?
--- @return table
local function entry(overrides)
  return vim.tbl_extend("force", {
    path = "lua/mod",
    rationale = "every mutant of it runs in a process no spec drives",
  }, overrides or {})
end

describe("ntf.core.mutation.exclude.load", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("loads the entries", function()
    local file = helper.test_data:create_file("exclude.json", vim.json.encode({ version = 1, entries = { entry() } }))

    local loaded = assert(exclude.load(file))

    assert.equal(1, #loaded)
    assert.equal("lua/mod", loaded[1].path)
  end)

  it("rejects a file that is not JSON", function()
    local file = helper.test_data:create_file("exclude.json", "not json")

    assert.match("invalid JSON", exclude.load(file))
  end)

  it("rejects an unsupported version", function()
    local file = helper.test_data:create_file("exclude.json", vim.json.encode({ version = 2, entries = {} }))

    assert.match("expected version 1", exclude.load(file))
  end)

  it("rejects an entry that lacks a field", function()
    local incomplete = entry()
    incomplete.path = nil
    local file =
      helper.test_data:create_file("exclude.json", vim.json.encode({ version = 1, entries = { incomplete } }))

    assert.match("entries%[1%] needs a string path", exclude.load(file))
  end)

  it("rejects a blank rationale", function()
    local file = helper.test_data:create_file(
      "exclude.json",
      vim.json.encode({ version = 1, entries = { entry({ rationale = " " }) } })
    )

    assert.match("entries%[1%] needs a non%-empty rationale", exclude.load(file))
  end)

  it("rejects an entry that is not an object", function()
    local file = helper.test_data:create_file("exclude.json", vim.json.encode({ version = 1, entries = { "nope" } }))

    assert.match("entries%[1%] is not an object", exclude.load(file))
  end)

  it("rejects a file that cannot be read", function()
    assert.match("cannot be read", exclude.load(vim.fs.joinpath(helper.test_data.full_path, "missing.json")))
  end)

  it("rejects a document whose entries are not an array", function()
    local file = helper.test_data:create_file("exclude.json", vim.json.encode({ version = 1, entries = "nope" }))

    assert.match("expected an entries array", exclude.load(file))
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
