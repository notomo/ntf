local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local work = require("ntf.core.controller.work")
local pool = require("ntf.core.controller.pool")
local driver = require("ntf.core.worker.driver")
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

local slow_test = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("sleeps", function()
    vim.uv.sleep(300)
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

--- @type integer how long a worker waits for the other slots to fill before giving up on them
local rendezvous_ms = 5000

--- @type integer how long a worker holds its slot past the rendezvous, so peers that met there overlap by more than the poll that found them
local hold_ms = 50

--- @param count integer tests the spec holds
--- @param jobs integer workers the run may hold at once
--- @param dir string directory the tests record their spans in
--- @return string # spec source
local function spec_recording_spans(count, jobs, dir)
  local tests = {}
  for index = 1, count do
    table.insert(
      tests,
      ([[
  ntf.it("slot %d", function()
    local path = vim.fs.joinpath(%q, "%d")
    local started = vim.uv.hrtime() * 1e-6
    vim.fn.writefile({ ("%%.3f"):format(started) }, path)
    vim.wait(%d, function()
      return #vim.fn.readdir(%q) >= %d
    end, 10)
    vim.uv.sleep(%d)
    vim.fn.writefile({ ("%%.3f"):format(started), ("%%.3f"):format(vim.uv.hrtime() * 1e-6) }, path)
  end)
]]):format(index, dir, index, rendezvous_ms, dir, jobs, hold_ms)
    )
  end
  return ([[
local ntf = require("ntf")
ntf.describe("x", function()
%s
end)
]]):format(table.concat(tests))
end

--- @param dir string directory the workers recorded their spans in
--- @return integer # the most workers that held a slot at one instant
local function most_at_once(dir)
  local events = {}
  for _, name in ipairs(vim.fn.readdir(dir)) do
    local lines = vim.fn.readfile(vim.fs.joinpath(dir, name))
    assert(#lines == 2, "a worker recorded no span: " .. name)
    table.insert(events, { at = tonumber(lines[1]), delta = 1 })
    table.insert(events, { at = tonumber(lines[2]), delta = -1 })
  end
  table.sort(events, function(a, b)
    if a.at ~= b.at then
      return a.at < b.at
    end
    return a.delta < b.delta
  end)

  local held, most = 0, 0
  for _, event in ipairs(events) do
    held = held + event.delta
    most = math.max(most, held)
  end
  return most
end

--- @param items table[] the NtfWorkItems of the run
--- @param opts table run options merged over the defaults
--- @return table results, table coverage, table timing
local function run(items, opts)
  return pool.run(items, vim.tbl_extend("force", { root = helper.root, budget = 30000 }, opts))
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

    local results = run(items, { root = helper.root })

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

    local results = run(items, { root = helper.root, jobs = 1 })

    assert.equal(#items, #results)
  end)

  it("waits out a worker slower than a fraction of a second, cutting off only a run that never finishes", function()
    local items = work.plan({ helper.write_spec(slow_test) })

    local results = run(items, { root = helper.root })

    assert.equal(1, #results)
    assert.equal("passed", results[1].status)
  end)

  it("kills the workers still running when a callback aborts the run", function()
    local items = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("finishes at once", function() end)
  ntf.it("outlives the abort", function()
    vim.uv.sleep(3000)
  end)
end)
]]),
    })

    local ok = pcall(run, items, {
      root = helper.root,
      jobs = 2,
      on_item = function()
        error("aborted by the callback", 0)
      end,
    })

    assert.is_false(ok)
    assert.equal(0, driver.kill_all())
  end)

  it("gives up on a run that outlasts its budget, naming only the tests a worker still holds", function()
    local items = work.plan({
      helper.write_spec([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("finishes at once", function() end)
  ntf.it("never returns", function()
    while true do end
  end)
end)
]]),
    })

    local ok, err = pcall(run, items, { jobs = 1, budget = 1000 })

    assert.is_false(ok)
    assert.match("1 of 2 tests never reported back, 1 of them from a worker it had launched", err)
    assert.match("x never returns", err)
    assert.no.match("finishes at once", err)
  end)

  it("merges nothing and calls no coverage callback when coverage is off", function()
    local items = work.plan({ helper.write_spec(one_test) })
    local called = false

    local _, coverage = run(items, {
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

    local _, coverage = run(items, { root = helper.root, coverage = true })

    local the_module_every_spec_requires = vim.fs.joinpath(vim.fs.normalize(vim.fn.getcwd()), "lua/ntf/init.lua")
    assert.is_true(coverage[the_module_every_spec_requires].max > 0)
    local _, seeded = counted(coverage)
    assert.is_true(seeded > 0)
  end)

  it("leaves the spec tree out of the files it measures", function()
    local items = work.plan({ helper.write_spec(one_test) })

    local _, coverage = run(items, { root = helper.root, coverage = true })

    local under_spec = vim.tbl_filter(function(path)
      return path:find("/spec/", 1, true) ~= nil
    end, vim.tbl_keys(coverage))
    assert.same({}, under_spec)
  end)

  it("streams a worker's captured output to on_output", function()
    local items = work.plan({ helper.write_spec(printing_test) })
    local outputs = {}

    run(items, {
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

    local results = run(items, { root = helper.root })

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
      run(items, {
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
    local _, _, timing = run(items, { root = helper.root, jobs = 1 })
    local the_run_took = (vim.uv.hrtime() - before) * 1e-9

    assert.is_true(timing.elapsed > 0)
    assert.is_true(timing.elapsed <= the_run_took)
    assert.is_true(timing.worker > 0)
    assert.is_true(timing.worker <= timing.elapsed)
  end)

  it("reports the jobs it ran with", function()
    local items = work.plan({ helper.write_spec(one_test) })

    local _, _, timing = run(items, { root = helper.root, jobs = 1 })

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
    run(items, {
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

  it("fills the jobs it was given and no more, so an item waits for a slot to free", function()
    local jobs = 2
    local dir = helper.test_data:create_dir("slots")
    local items = work.plan({ helper.write_spec(spec_recording_spans(2 * jobs, jobs, dir)) })

    run(items, { root = helper.root, jobs = jobs })

    assert.equal(jobs, most_at_once(dir))
  end)
end)
