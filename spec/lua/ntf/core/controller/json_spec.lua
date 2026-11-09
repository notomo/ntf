local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local json = require("ntf.core.controller.json")

local spec_path = "spec/x_spec.lua"
local absolute_spec_path = vim.fs.joinpath(vim.fn.getcwd(), spec_path)

--- @param overrides table? what the item differs in from one test of one file
--- @return NtfWorkItem
local function item(overrides)
  return vim.tbl_deep_extend("force", {
    file = spec_path,
    node_id = "1",
    names = { "group", "adds" },
    trace = { source = "@" .. absolute_spec_path, line = 12 },
    leaves_count = 1,
  }, overrides or {})
end

--- @param overrides table? what the result differs in from a passing test
--- @return NtfResult
local function result(overrides)
  return vim.tbl_deep_extend("force", {
    id = "1",
    name = "adds",
    names = { "group", "adds" },
    trace = { source = "@" .. absolute_spec_path, line = 12 },
    status = "passed",
    duration = 0.5,
    file = spec_path,
  }, overrides or {})
end

--- @type NtfRunTiming
local timing = {
  elapsed = 1.5,
  worker = 3,
  killed = { seconds = 0, workers = 0 },
  jobs = 4,
}

--- @param text string
--- @return table
local function decode(text)
  return vim.json.decode(text)
end

describe("ntf.core.controller.json.list", function()
  it("spells a test with its file relative to the working directory, its line and its names", function()
    local doc = decode(json.list({ item() }, {}))

    assert.equal(spec_path, doc.tests[1].file)
    assert.equal(12, doc.tests[1].row)
    assert.same({ "group", "adds" }, doc.tests[1].names)
    assert.equal("group adds", doc.tests[1].full_name)
  end)

  it("takes the file from where the test was declared, not from the one it was planned from", function()
    local doc = decode(json.list({ item({ file = "/elsewhere/x_spec.lua" }) }, {}))

    assert.equal(spec_path, doc.tests[1].file)
  end)

  it("falls back to the planned file, without a line, where the test carries no trace", function()
    local doc = decode(json.list({ { file = spec_path, node_id = "1", names = { "adds" }, leaves_count = 1 } }, {}))

    assert.equal(spec_path, doc.tests[1].file)
    assert.is_nil(doc.tests[1].row)
  end)

  it("keeps a name the source spelled over several lines, and escapes it in the full name", function()
    local doc = decode(json.list({ item({ names = { "group", "select (\nhoge\n)" } }) }, {}))

    assert.same({ "group", "select (\nhoge\n)" }, doc.tests[1].names)
    assert.equal("group select (\\nhoge\\n)", doc.tests[1].full_name)
  end)

  it("spells a load error with its file relative to the working directory and its message", function()
    local doc = decode(json.list({}, { { file = absolute_spec_path, message = "boom" } }))

    assert.same({ file = spec_path, message = "boom" }, doc.load_errors[1])
  end)

  it("renders a listing of nothing as empty arrays, not as empty objects", function()
    local text = json.list({}, {})

    assert.match('"tests":%[%]', text)
    assert.match('"load_errors":%[%]', text)
  end)
end)

describe("ntf.core.controller.json.run", function()
  it("spells a result with its status and what it raised", function()
    local doc =
      decode(json.run({ result({ status = "failed", message = "1 ~= 2", traceback = "at line 5" }) }, {}, timing, {}))

    assert.equal("failed", doc.results[1].status)
    assert.equal("1 ~= 2", doc.results[1].message)
    assert.equal("at line 5", doc.results[1].traceback)
    assert.equal(0.5, doc.results[1].duration)
  end)

  it("leaves what a passing test did not raise out of its entry", function()
    local text = json.run({ result() }, {}, timing, {})

    assert.no.match('"message"', text)
    assert.no.match('"traceback"', text)
  end)

  it("takes the spec file off the result where it carries no trace", function()
    local untraced = result({ names = { "adds" } })
    untraced.trace = nil
    local doc = decode(json.run({ untraced }, {}, timing, {}))

    assert.equal(spec_path, doc.results[1].file)
    assert.is_nil(doc.results[1].row)
  end)

  it("attaches what a test printed to its result", function()
    local doc = decode(json.run({ result() }, {}, timing, {
      outputs = { { file = spec_path, name = "group adds", output = "from print" } },
    }))

    assert.equal("from print", doc.results[1].output)
    assert.is_nil(doc.outputs)
  end)

  it("leaves the printed blobs out where the run printed nothing", function()
    local text = json.run({ result() }, {}, timing, {})

    assert.no.match('"output"', text)
  end)

  it("keeps the output no result answered for, in the order the workers printed it", function()
    local doc = decode(json.run({}, {}, timing, {
      outputs = {
        { file = "spec/b_spec.lua", name = "b", output = "third" },
        { file = "spec/a_spec.lua", name = "z", output = "second" },
        { file = "spec/a_spec.lua", name = "a", output = "first" },
      },
    }))

    assert.same({
      { file = "spec/b_spec.lua", name = "b", output = "third" },
      { file = "spec/a_spec.lua", name = "z", output = "second" },
      { file = "spec/a_spec.lua", name = "a", output = "first" },
    }, doc.outputs)
  end)

  it("carries the timing the run took", function()
    local doc = decode(json.run({ result() }, {}, timing, {}))

    assert.same(timing, doc.timing)
  end)

  it("leaves the budget out of a run that finished", function()
    local text = json.run({ result() }, {}, timing, {})

    assert.no.match('"gave_up"', text)
  end)

  it("spells the budget a run that gave up spent", function()
    local doc = decode(json.run({ result() }, {}, timing, {
      gave_up = { budget = 60000, unfinished = 2, total = 10, unit = "test", launched = { "one" } },
    }))

    assert.equal(2, doc.gave_up.unfinished)
    assert.equal("test", doc.gave_up.unit)
  end)
end)
