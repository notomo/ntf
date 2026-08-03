local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local work = require("ntf.core.controller.work")
local pool = require("ntf.core.controller.pool")
local helper = require("ntf.test.helper")

local one_test = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]]

local printing_test = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("prints", function()
    print("hello from the worker")
  end)
end)
]]

--- @param coverage table merged per-file line hit counts
--- @return integer measured, integer seeded
local function counted(coverage)
  local measured, seeded = 0, 0
  for _, entry in pairs(coverage) do
    if entry.max > 0 then
      measured = measured + 1
    else
      seeded = seeded + 1
    end
  end
  return measured, seeded
end

describe("ntf.core.controller.pool.run", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("returns one result per work item", function()
    local items = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("one", function() end)
  ntf.it("two", function() end)
  ntf.it("three", function() end)
end)
]]),
    })

    local results = pool.run(items, { root = helper.root })

    assert.equal(#items, #results)
  end)

  it("keeps waiting for the item a single worker only starts once the first is done", function()
    local items = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("one", function() end)
  ntf.it("two", function() end)
end)
]]),
    })

    local results = pool.run(items, { root = helper.root, jobs = 1 })

    assert.equal(#items, #results)
  end)

  it("merges nothing and calls no coverage callback when coverage is off", function()
    local items = work.plan({ helper.write_spec(one_test) })
    local called = false

    local _, coverage = pool.run(items, {
      root = helper.root,
      on_item_coverage = function()
        called = true
      end,
    })

    assert.is_false(called)
    assert.same({}, coverage)
  end)

  it("lists every measurable file, keeping the counts of the ones a worker ran", function()
    local items = work.plan({ helper.write_spec(one_test) })

    local _, coverage = pool.run(items, { root = helper.root, coverage = true })

    local the_module_every_spec_requires = vim.fs.joinpath(vim.fs.normalize(vim.fn.getcwd()), "lua/ntf/init.lua")
    assert.is_true(coverage[the_module_every_spec_requires].max > 0)
    local _, seeded = counted(coverage)
    assert.is_true(seeded > 0)
  end)

  it("leaves the spec tree out of the files it measures", function()
    local items = work.plan({ helper.write_spec(one_test) })

    local _, coverage = pool.run(items, { root = helper.root, coverage = true })

    local under_spec = vim.tbl_filter(function(path)
      return path:find("/spec/", 1, true) ~= nil
    end, vim.tbl_keys(coverage))
    assert.same({}, under_spec)
  end)

  it("streams a worker's captured output to on_output", function()
    local items = work.plan({ helper.write_spec(printing_test) })
    local outputs = {}

    pool.run(items, {
      root = helper.root,
      on_output = function(out)
        table.insert(outputs, out.output)
      end,
    })

    assert.equal(1, #outputs)
    assert.match("hello from the worker", outputs[1])
  end)

  it("runs a worker that printed even with no on_output to hand it to", function()
    local items = work.plan({ helper.write_spec(printing_test) })

    local results = pool.run(items, { root = helper.root })

    assert.equal("passed", results[1].status)
  end)

  it("aborts the run when a worker callback raises an internal error", function()
    local file = helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]])
    local items = work.plan({ file })

    local ok, err = pcall(function()
      pool.run(items, {
        root = helper.root,
        on_item = function()
          error("boom in callback")
        end,
      })
    end)

    assert.is_false(ok)
    local first_frame = vim.split(tostring(err), "\n", { plain = true })[1]
    local raised_where_the_callback_is, with_nothing_prepended = "pool_spec%.lua:%d+: boom in callback$", "^%S*"
    assert.match(with_nothing_prepended .. raised_where_the_callback_is, first_frame)
  end)

  it("times the run and the worker processes in seconds, a lone worker never outlasting the run", function()
    local items = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("one", function() end)
  ntf.it("two", function() end)
end)
]]),
    })

    local before = vim.uv.hrtime()
    local _, _, timing = pool.run(items, { root = helper.root, jobs = 1 })
    local the_run_took = (vim.uv.hrtime() - before) * 1e-9

    assert.is_true(timing.elapsed > 0)
    assert.is_true(timing.elapsed <= the_run_took)
    assert.is_true(timing.worker > 0)
    assert.is_true(timing.worker <= timing.elapsed)
  end)

  it("reports the jobs it ran with", function()
    local items = work.plan({ helper.write_spec(one_test) })

    local _, _, timing = pool.run(items, { root = helper.root, jobs = 1 })

    assert.equal(1, timing.jobs)
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
