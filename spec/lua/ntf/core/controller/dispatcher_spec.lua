local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local runner = require("ntf.core.controller.dispatcher")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("math", function()
  it("adds", function() end)
  it("subtracts", function() end)
end)

describe("string", function()
  it("adds", function() end)
end)
]]

-- Flatten every planned item back into the leaf ids it would run.
local function planned_ids(items)
  local ids = {}
  for _, item in ipairs(items) do
    vim.list_extend(ids, item.node_ids)
  end
  return ids
end

describe("ntf.core.controller.dispatcher.plan", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("keeps every leaf when no filter is given", function()
    local file = helper.write_spec(source)
    local items = runner.plan({ file })

    assert.same({ "1.1", "1.2", "2.1" }, planned_ids(items))
  end)

  it("keeps only leaves whose full name matches the filter", function()
    local file = helper.write_spec(source)
    local items = runner.plan({ file }, "adds")

    -- "math adds" and "string adds" match; "math subtracts" is dropped
    assert.same({ "1.1", "2.1" }, planned_ids(items))
  end)

  it("matches the filter as a Lua pattern against the full name", function()
    local file = helper.write_spec(source)
    local items = runner.plan({ file }, "^math")

    assert.same({ "1.1", "1.2" }, planned_ids(items))
  end)

  it("drops work items that have no matching leaf", function()
    local file = helper.write_spec(source)
    local items = runner.plan({ file }, "subtracts")

    assert.equal(1, #items)
    assert.same({ "1.2" }, items[1].node_ids)
  end)

  it("yields no items when the filter matches nothing", function()
    local file = helper.write_spec(source)
    local items = runner.plan({ file }, "nope")

    assert.equal(0, #items)
  end)

  it("carries an it-level timeout onto its item", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("A", function()
  it("slow", function() end, { timeout = 1000 })
  it("normal", function() end)
end)
]])
    local items = runner.plan({ file })

    assert.equal(1000, items[1].timeout)
    assert.equal(nil, items[2].timeout)
  end)

  it("schedules a describe whose body errored as its own work item", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("broken", function()
  it("never reached", function() end)
  error("describe body blew up")
end)
]])
    local items, load_errors = runner.plan({ file })

    -- The file loaded, so it is not a file-level load error; the broken
    -- describe is scheduled as a leaf so its error gets reported on execution.
    assert.equal(0, #load_errors)
    assert.same({ "1" }, planned_ids(items))
  end)
end)

describe("ntf.core.controller.dispatcher.run", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("aborts the run when a worker callback raises an internal error", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]])
    local items = runner.plan({ file })

    -- on_item fires for every finished worker; throwing here stands in for any
    -- bug in the result/output handling. Such an error must surface, not hang.
    local ok, err = pcall(function()
      runner.run(items, {
        root = helper.root,
        on_item = function()
          error("boom in callback")
        end,
      })
    end)

    assert.is_false(ok)
    assert.match("boom in callback", err)
  end)
end)
