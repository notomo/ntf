local tree = require("ntf.core.tree")
local run = require("ntf.core.run")
local helper = require("ntf.test.helper")

local source = [[
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
