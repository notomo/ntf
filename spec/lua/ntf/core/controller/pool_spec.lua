local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local work = require("ntf.core.controller.work")
local pool = require("ntf.core.controller.pool")
local helper = require("ntf.test.helper")

describe("ntf.core.controller.pool.run", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("aborts the run when a worker callback raises an internal error", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]])
    local items = work.plan({ file })

    -- on_item fires for every finished worker; throwing here stands in for any
    -- bug in the result/output handling. Such an error must surface, not hang.
    local ok, err = pcall(function()
      pool.run(items, {
        root = helper.root,
        on_item = function()
          error("boom in callback")
        end,
      })
    end)

    assert.is_false(ok)
    assert.match("boom in callback", err)
  end)

  it("hands each worker's own coverage to on_item_coverage", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
  ntf.it("runs too", function() end)
end)
]])
    local items = work.plan({ file })

    local calls = {}
    pool.run(items, {
      root = helper.root,
      coverage = true,
      on_item_coverage = function(item_index, coverage)
        table.insert(calls, { item_index = item_index, measured = coverage ~= nil })
      end,
    })
    table.sort(calls, function(a, b)
      return a.item_index < b.item_index
    end)

    assert.same({
      { item_index = 1, measured = true },
      { item_index = 2, measured = true },
    }, calls)
  end)
end)
