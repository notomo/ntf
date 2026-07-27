local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local driver = require("ntf.core.worker.driver")
local work = require("ntf.core.controller.work")
local helper = require("ntf.test.helper")

local function launch(item)
  local done
  driver.launch(item, { root = helper.root, cwd = helper.test_data.full_path, timeout = 30000 }, function(outcome)
    done = outcome
  end)
  vim.wait(30000, function()
    return done ~= nil
  end, 20)
  return assert(done, "the worker did not finish")
end

describe("ntf.core.worker.driver.launch", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports one result for the node it asked for", function()
    local item = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]]),
    })[1]

    local outcome = launch(item)

    assert.equal(1, #outcome.results)
    assert.equal("passed", outcome.results[1].status)
  end)

  it("errors on a worker that reported no result, since it was asked for exactly one node", function()
    local item = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]]),
    })[1]
    item.node_id = "a node the rebuilt tree does not hold"

    local outcome = launch(item)

    assert.equal(1, #outcome.results)
    assert.equal("error", outcome.results[1].status)
    assert.match("no result", outcome.results[1].message)
  end)
end)
