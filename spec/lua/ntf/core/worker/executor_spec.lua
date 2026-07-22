local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local tree = require("ntf.core.tree")
local executor = require("ntf.core.worker.executor")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending
local before_each, after_each = ntf.before_each, ntf.after_each
local finally = ntf.finally

_G.__NTF_LOG = {}
local log = function(entry)
  table.insert(_G.__NTF_LOG, entry)
end

describe("block", function()
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

describe("ntf.core.worker.executor.run", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports pass / fail / pending statuses", function()
    local root = tree.build(helper.write_spec(source))
    local results = executor.run(root, nil)

    assert.equal(3, #results)
    assert.equal("passed", results[1].status)
    assert.equal("failed", results[2].status)
    assert.equal("pending", results[3].status)
    assert.match("boom", results[2].message)
  end)

  it("runs before_each/after_each/finally per test", function()
    local root = tree.build(helper.write_spec(source))
    executor.run(root, nil)

    local passing_test = { "before", "it1", "finally1", "after" }
    local failing_test = { "before", "it2", "after" }
    local test_pending_from_inside_its_body = { "before", "after" }

    local log = rawget(_G, "__NTF_LOG")
    assert.same(vim.iter({ passing_test, failing_test, test_pending_from_inside_its_body }):flatten():totable(), log)
  end)

  it("runs only the selected leaf ids", function()
    local root = tree.build(helper.write_spec(source))
    local results = executor.run(root, { ["1.1"] = true })

    assert.equal(1, #results)
    assert.equal("passes", results[1].name)
  end)
end)

local broken_describe_source = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("outer", function()
  describe("broken", function()
    it("never reached", function() end)
    error("describe body blew up")
  end)

  it("sibling still runs", function() end)
end)
]]

describe("ntf.core.worker.executor.run describe-body errors", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports the errored describe and skips its children, but runs siblings", function()
    local root = tree.build(helper.write_spec(broken_describe_source))
    local results = executor.run(root, nil)

    assert.equal(2, #results)

    local broken = results[1]
    assert.equal("error", broken.status)
    assert.same({ "outer", "broken" }, broken.names)
    assert.match("describe body blew up", broken.message)
    assert.truthy(broken.trace)

    assert.equal("sibling still runs", results[2].name)
    assert.equal("passed", results[2].status)
  end)
end)
