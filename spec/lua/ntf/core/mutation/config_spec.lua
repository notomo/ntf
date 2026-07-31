local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local config = require("ntf.core.mutation.config")
local helper = require("ntf.test.helper")

--- @param overrides table?
--- @return table
local function baseline_entry(overrides)
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
local function exclude_entry(overrides)
  return vim.tbl_extend("force", {
    path = "lua/mod",
    rationale = "every mutant of it runs in a process no spec drives",
  }, overrides or {})
end

--- @param document table
--- @return string # path of the written file
local function create_file(document)
  return helper.test_data:create_file("mutation.json", vim.json.encode(document))
end

describe("ntf.core.mutation.config.load", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("loads both sections", function()
    local file = create_file({
      version = 1,
      baseline = { baseline_entry() },
      exclude = { exclude_entry() },
    })

    local loaded = assert(config.load(file))

    assert.equal(1, #loaded.baseline)
    assert.equal("lua/mod.lua", loaded.baseline[1].path)
    assert.equal(7, loaded.baseline[1].col)
    assert.equal(1, #loaded.exclude)
    assert.equal("lua/mod", loaded.exclude[1].path)
  end)

  it("leaves a section out as empty", function()
    local file = create_file({ version = 1, exclude = { exclude_entry() } })

    local loaded = assert(config.load(file))

    assert.same({}, loaded.baseline)
    assert.equal(1, #loaded.exclude)
  end)

  it("rejects a file that is not JSON", function()
    local file = helper.test_data:create_file("mutation.json", "not json")

    assert.match("invalid JSON", config.load(file))
  end)

  it("rejects an unsupported version", function()
    local file = create_file({ version = 2 })

    assert.match("expected version 1", config.load(file))
  end)

  it("rejects a file that cannot be read", function()
    assert.match("cannot be read", config.load(vim.fs.joinpath(helper.test_data.full_path, "missing.json")))
  end)

  it("names the file it rejects", function()
    local file = create_file({ version = 2 })

    assert.match("%-%-mutation%-config " .. vim.pesc(file) .. ":", config.load(file))
  end)

  it("rejects a baseline that is not an array", function()
    local file = create_file({ version = 1, baseline = "nope" })

    assert.match("baseline is not an array", config.load(file))
  end)

  it("rejects an exclude that is not an array", function()
    local file = create_file({ version = 1, exclude = "nope" })

    assert.match("exclude is not an array", config.load(file))
  end)

  it("reports which baseline entry is invalid", function()
    local incomplete = baseline_entry()
    incomplete.line = nil
    local file = create_file({ version = 1, baseline = { baseline_entry(), incomplete } })

    assert.match("baseline%[2%] needs a string line", config.load(file))
  end)

  it("reports which exclude entry is invalid", function()
    local incomplete = exclude_entry()
    incomplete.rationale = nil
    local file = create_file({ version = 1, exclude = { exclude_entry(), incomplete } })

    assert.match("exclude%[2%] needs a string rationale", config.load(file))
  end)
end)
