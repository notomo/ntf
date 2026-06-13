local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local tree = require("ntf.core.tree")
local run = require("ntf.core.run")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending
local before_each, after_each = ntf.before_each, ntf.after_each
local setup, teardown, finally = ntf.setup, ntf.teardown, ntf.finally

_G.__NTF_LOG = {}
local log = function(entry)
  table.insert(_G.__NTF_LOG, entry)
end

describe("block", function()
  setup(function()
    log("setup")
  end)
  teardown(function()
    log("teardown")
  end)
  before_each(function()
    log("before")
  end)
  after_each(function()
    log("after")
  end)

  it("passes", function()
    log("it1")
    finally(function()
      log("finally1")
    end)
  end)

  it("fails", function()
    log("it2")
    error("boom")
  end)

  it("pends", function()
    pending("later")
  end)
end)
]]

describe("ntf.core.run.execute", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports pass / fail / pending statuses", function()
    local root = tree.build(helper.write_spec(source))
    local results = run.execute(root, nil, {})

    assert.equal(3, #results)
    assert.equal("passed", results[1].status)
    assert.equal("failed", results[2].status)
    assert.equal("pending", results[3].status)
    assert.match("boom", results[2].message)
  end)

  it("runs setup/teardown once and before_each/after_each/finally per test", function()
    local root = tree.build(helper.write_spec(source))
    run.execute(root, nil, {})

    -- the third test calls pending() inside its body, so its before/after_each
    -- hooks still run (runtime pending != declaration pending)
    assert.same({
      "setup",
      "before",
      "it1",
      "finally1",
      "after",
      "before",
      "it2",
      "after",
      "before",
      "after",
      "teardown",
    }, _G.__NTF_LOG)
  end)

  it("runs only the selected leaf ids", function()
    local root = tree.build(helper.write_spec(source))
    local results = run.execute(root, { ["1.1"] = true }, {})

    assert.equal(1, #results)
    assert.equal("passes", results[1].name)
  end)
end)

local output_source = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("block", function()
  it("prints", function()
    print("hello", "world")
    io.write("raw\n")
  end)

  it("prints then fails", function()
    print("before boom")
    error("boom")
  end)

  it("is silenced", function()
    print("invisible")
  end, { output = "never" })

  it("stays quiet", function() end)
end)
]]

describe("ntf.core.run.execute output capture", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("attaches captured print/io.write output to the test that emitted it", function()
    local root = tree.build(helper.write_spec(output_source))
    local results = run.execute(root, nil, {})

    -- print joins args with a tab and appends a newline; io.write is verbatim
    assert.equal("hello\tworld\nraw\n", results[1].output)
  end)

  it("keeps output on a failing test alongside its error", function()
    local root = tree.build(helper.write_spec(output_source))
    local results = run.execute(root, nil, {})

    assert.equal("failed", results[2].status)
    assert.equal("before boom\n", results[2].output)
  end)

  it("drops output when the test opts out with output = never", function()
    local root = tree.build(helper.write_spec(output_source))
    local results = run.execute(root, nil, {})

    assert.equal("is silenced", results[3].name)
    assert.is_nil(results[3].output)
  end)

  it("leaves output unset when a test emits nothing", function()
    local root = tree.build(helper.write_spec(output_source))
    local results = run.execute(root, nil, {})

    assert.equal("stays quiet", results[4].name)
    assert.is_nil(results[4].output)
  end)

  it("restores the real print/io.write after running", function()
    local before = print
    local root = tree.build(helper.write_spec(output_source))
    run.execute(root, nil, {})

    assert.equal(before, print)
  end)
end)
