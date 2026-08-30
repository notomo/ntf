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
    operators = "all",
    rationale = "every mutant of it runs in a process no spec drives",
  }, overrides or {})
end

--- @param overrides table?
--- @return table
local function exclude_spec_entry(overrides)
  return vim.tbl_extend("force", {
    path = "spec/e2e_spec.lua",
    rationale = "as a trial it drives the whole CLI to reach what a unit spec reaches in-process",
  }, overrides or {})
end

--- @param document table
--- @return string # path of the written file
local function create_file(document)
  local with_operators = vim.tbl_extend("keep", document, { operators = "all" })
  return helper.test_data:create_file("mutation.json", vim.json.encode(with_operators))
end

describe("ntf.core.mutation.config.load", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("loads every section", function()
    local file = create_file({
      version = 1,
      baseline = { baseline_entry() },
      exclude = { exclude_entry() },
      exclude_spec = { exclude_spec_entry() },
    })

    local loaded = assert(config.load(file))

    assert.equal(1, #loaded.baseline)
    assert.equal("lua/mod.lua", loaded.baseline[1].path)
    assert.equal(1, #loaded.exclude)
    assert.equal("lua/mod", loaded.exclude[1].path)
    assert.equal(1, #loaded.exclude_spec)
    assert.equal("spec/e2e_spec.lua", loaded.exclude_spec[1].path)
  end)

  it("takes a baseline entry's column back from the one the document counts from 1", function()
    local file = create_file({ version = 1, baseline = { baseline_entry({ col = 7 }) } })

    local loaded = assert(config.load(file))

    local zero_based_as_every_site_counts_it = 6
    assert.equal(zero_based_as_every_site_counts_it, loaded.baseline[1].col)
  end)

  it("leaves a section out as empty", function()
    local file = create_file({ version = 1, exclude = { exclude_entry() } })

    local loaded = assert(config.load(file))

    assert.same({}, loaded.baseline)
    assert.same({}, loaded.exclude_spec)
    assert.equal(1, #loaded.exclude)
  end)

  it("loads the operators the config adopted", function()
    local file = create_file({ version = 1, operators = { "swap-relational" } })

    local loaded = assert(config.load(file))

    assert.same({ "swap-relational" }, loaded.operators)
  end)

  it("requires operators, which no default stands in for", function()
    local file = helper.test_data:create_file("mutation.json", vim.json.encode({ version = 1 }))

    assert.match('operators needs to be "all" or a non%-empty array', config.load(file))
  end)

  it("rejects an empty operators array, which names no operator at all", function()
    local file = create_file({ version = 1, operators = {} })

    assert.match('operators needs to be "all" or a non%-empty array', config.load(file))
  end)

  it("rejects an operators name no operator answers to, which is how a typo is caught", function()
    local file = create_file({ version = 1, operators = { "swap-relational", "swap-relatinal" } })

    assert.match('operators names an operator no run produces: "swap%-relatinal"', config.load(file))
  end)

  it("closes the file it read", function()
    local file = create_file({ version = 1 })

    assert.is_false(helper.leaves_file_open(file, function()
      config.load(file)
    end))
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

    assert.match("%-%-config " .. vim.pesc(file) .. ":", config.load(file))
  end)

  it("rejects a baseline that is not an array", function()
    local file = create_file({ version = 1, baseline = "nope" })

    assert.match("baseline is not an array", config.load(file))
  end)

  it("rejects an exclude that is not an array", function()
    local file = create_file({ version = 1, exclude = "nope" })

    assert.match("exclude is not an array", config.load(file))
  end)

  it("rejects a baseline written as an object, whose entries an array walk reaches none of", function()
    local file = create_file({ version = 1, baseline = { ["lua/mod.lua"] = baseline_entry() } })

    assert.match("baseline is not an array", config.load(file))
  end)

  it("rejects an exclude written as an object, which would leave every path it names mutated", function()
    local file = create_file({ version = 1, exclude = { ["lua/mod"] = exclude_entry() } })

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

  it("holds an exclude entry to the operators an exclude_spec entry does not take", function()
    local unscoped = exclude_entry()
    unscoped.operators = nil
    local file = create_file({ version = 1, exclude = { unscoped } })

    assert.match('exclude%[1%] needs an operators of "all"', config.load(file))
  end)

  it("rejects an exclude_spec entry that names operators", function()
    local file = create_file({ version = 1, exclude_spec = { exclude_spec_entry({ operators = "all" }) } })

    assert.match("exclude_spec%[1%] takes no operators", config.load(file))
  end)

  it("reports which exclude_spec entry is invalid", function()
    local incomplete = exclude_spec_entry()
    incomplete.rationale = nil
    local file = create_file({ version = 1, exclude_spec = { exclude_spec_entry(), incomplete } })

    assert.match("exclude_spec%[2%] needs a string rationale", config.load(file))
  end)

  it("rejects a key no run reads, which a write would otherwise drop without a word", function()
    local file = create_file({ version = 1, note = "kept for the next reviewer" })

    assert.match("spells keys no run reads: note", config.load(file))
  end)

  it("rejects a misspelled section name, whose entries would otherwise be left out of every run", function()
    local file = create_file({ version = 1, excludes = { exclude_entry() } })

    assert.match("spells keys no run reads: excludes", config.load(file))
  end)

  it("rejects a baseline entry field no run reads", function()
    local file =
      create_file({ version = 1, baseline = { baseline_entry(), baseline_entry({ reviewed_by = "someone" }) } })

    assert.match("baseline%[2%] spells fields no run reads: reviewed_by", config.load(file))
  end)

  it("rejects an exclude entry field no run reads", function()
    local file = create_file({ version = 1, exclude = { exclude_entry({ note = "why" }) } })

    assert.match("exclude%[1%] spells fields no run reads: note", config.load(file))
  end)
end)

describe("ntf.core.mutation.config.format", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  --- @param overrides table?
  --- @return table
  local function document(overrides)
    return vim.tbl_extend(
      "force",
      { operators = "all", baseline = {}, exclude = {}, exclude_spec = {} },
      overrides or {}
    )
  end

  it("writes an entry field by field, in the order the document carries them", function()
    local text = config.format(document({ baseline = { baseline_entry({ invariant_spec = "mod takes the min" }) } }))

    assert.equal(
      table.concat({
        "{",
        '  "version": 1,',
        '  "operators": "all",',
        '  "baseline": [',
        "    {",
        '      "path": "lua/mod.lua",',
        '      "col": 8,',
        '      "operator": "swap-relational",',
        '      "original": "<",',
        '      "replacement": "<=",',
        '      "line": "  if a < b then",',
        '      "rationale": "min(1, 2) is 1 either way",',
        '      "invariant_spec": "mod takes the min"',
        "    }",
        "  ]",
        "}",
        "",
      }, "\n"),
      text
    )
  end)

  it("writes a baseline entry's column as the one every report counts from 1", function()
    local text = config.format(document({ baseline = { baseline_entry({ col = 7 }) } }))

    assert.match('"col": 8,', text)
  end)

  it("leaves out a field the entry does not carry", function()
    local text = config.format(document({ baseline = { baseline_entry() } }))

    assert.no.match("invariant_spec", text)
  end)

  it("leaves out a section with no entries", function()
    local text = config.format(document())

    assert.equal('{\n  "version": 1,\n  "operators": "all"\n}\n', text)
  end)

  it("writes the adopted operators a line at a time", function()
    local text = config.format(document({ operators = { "swap-relational", "swap-boolean" } }))

    assert.equal(
      table.concat({
        "{",
        '  "version": 1,',
        '  "operators": [',
        '    "swap-relational",',
        '    "swap-boolean"',
        "  ]",
        "}",
        "",
      }, "\n"),
      text
    )
  end)

  it("separates the entries of a section", function()
    local text = config.format(document({
      baseline = { baseline_entry(), baseline_entry({ col = 9 }) },
    }))

    assert.match("    },\n    {\n", text)
  end)

  it("writes every section it has entries for", function()
    local text = config.format(document({
      baseline = { baseline_entry() },
      exclude = { exclude_entry() },
      exclude_spec = { exclude_spec_entry() },
    }))

    assert.match('  "baseline": %[\n', text)
    assert.match('  "exclude": %[\n', text)
    assert.match('  "exclude_spec": %[\n', text)
  end)

  it("writes an operators array a line at a time", function()
    local text = config.format(document({
      exclude = { exclude_entry({ operators = { "swap-relational", "swap-boolean" } }) },
    }))

    assert.match('      "operators": %[\n        "swap%-relational",\n        "swap%-boolean"\n      %],\n', text)
  end)

  it("escapes what a JSON string has to escape, leaving what it does not alone", function()
    local text = config.format(document({
      baseline = { baseline_entry({ line = '  return "a\\b" -- \225\189\136' }) },
    }))

    assert.match('"line": "  return \\"a\\\\b\\" %-%- \225\189\136"', text)
  end)

  it("writes what load reads back unchanged", function()
    local written = document({
      baseline = { baseline_entry({ invariant_spec = "mod takes the min" }) },
      exclude = { exclude_entry() },
      exclude_spec = { exclude_spec_entry() },
    })
    local file = helper.test_data:create_file("written.json", config.format(written))

    local loaded = assert(config.load(file))

    assert.same(written, loaded)
  end)
end)

describe("ntf.core.mutation.config.write", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("writes the document to the file", function()
    local file = helper.test_data:create_file("mutation.json", "")
    local document = { operators = "all", baseline = { baseline_entry() }, exclude = {}, exclude_spec = {} }

    config.write(file, document)

    assert.equal(config.format(document), table.concat(vim.fn.readfile(file), "\n") .. "\n")
  end)

  it("leaves no temporary file beside the document, having renamed one into place", function()
    local dir = helper.test_data:path("policy")
    local file = helper.test_data:create_file("policy/mutation.json", "")

    config.write(file, { operators = "all", baseline = {}, exclude = {}, exclude_spec = {} })

    assert.same({ "mutation.json" }, vim.fn.readdir(dir))
  end)
end)
