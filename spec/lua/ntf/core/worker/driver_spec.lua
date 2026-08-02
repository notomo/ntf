local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local driver = require("ntf.core.worker.driver")
local watchdog = require("ntf.core.worker.watchdog")
local work = require("ntf.core.controller.work")
local helper = require("ntf.test.helper")

local ONE_TEST = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("runs", function() end)
end)
]]

local NEVER_FINISHES = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("spins", function()
    while true do end
  end)
end)
]]

--- @param source string
--- @return table # one NtfWorkItem
local function item_of(source)
  return work.plan({ helper.write_spec(source) })[1]
end

--- @param item table one NtfWorkItem
--- @param opts table? launch options merged over the defaults
--- @param wait_ms integer? how long to wait for the worker (default 30000)
--- @return table # one NtfWorkerOutcome
local function launch(item, opts, wait_ms)
  local done
  local launch_opts =
    vim.tbl_extend("force", { root = helper.root, cwd = helper.test_data.full_path, timeout = 30000 }, opts or {})
  driver.launch(item, launch_opts, function(outcome)
    done = outcome
  end)
  vim.wait(wait_ms or 30000, function()
    return done ~= nil
  end, 20)
  return assert(done, "the worker did not finish")
end

describe("ntf.core.worker.driver.launch", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports one result for the node it asked for", function()
    local outcome = launch(item_of(ONE_TEST))

    assert.equal(1, #outcome.results)
    assert.equal("passed", outcome.results[1].status)
  end)

  it("errors on a worker that reported no result, since it was asked for exactly one node", function()
    local item = item_of(ONE_TEST)
    item.node_id = "a node the rebuilt tree does not hold"

    local outcome = launch(item)

    assert.equal(1, #outcome.results)
    assert.equal("error", outcome.results[1].status)
    assert.match("no result", outcome.results[1].message)
  end)

  it("measures no coverage for a run that did not ask for any", function()
    local outcome = launch(item_of(ONE_TEST))

    assert.is_nil(outcome.coverage)
  end)

  it("hands back a printing worker's output under the test's full name", function()
    local outcome = launch(item_of([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("prints", function()
    print("hello from the worker")
  end)
end)
]]))

    assert.match("hello from the worker", outcome.output.output)
    assert.equal("x prints", outcome.output.name)
  end)

  it("normalizes the line endings of a worker that wrote carriage returns", function()
    -- WHY: the C runtime opens a worker's stdout in text mode on Windows, where
    -- it writes a carriage return of its own before every newline, so a written
    -- pair arrives there as a doubled one that outlives the normalization.
    -- NOT: io.write, which goes through that runtime.
    local outcome = launch(item_of([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("prints crlf", function()
    vim.uv.fs_write(1, "first\r\nsecond\r\n")
  end)
end)
]]))

    assert.match("first\nsecond", outcome.output.output)
    assert.no.match("\r", outcome.output.output)
  end)

  it("closes the timeout timer once the worker is done, leaving none behind", function()
    local function live_timers()
      local count = 0
      vim.uv.walk(function(handle)
        if handle:get_type() == "timer" and not handle:is_closing() then
          count = count + 1
        end
      end)
      return count
    end
    local before = live_timers()

    launch(item_of(ONE_TEST), { timeout = 30000 })

    assert.equal(before, live_timers())
  end)

  it("hands back nothing for a worker that stayed silent", function()
    local outcome = launch(item_of(ONE_TEST))

    assert.is_nil(outcome.output)
  end)

  it("hands back nothing for a worker that died before emitting its block", function()
    local item = item_of(ONE_TEST)
    vim.fn.writefile({ 'io.stderr:write("worker exploded")', "os.exit(1)" }, item.file)

    local outcome = launch(item)

    assert.is_nil(outcome.output)
    assert.equal("error", outcome.results[1].status)
    assert.match("worker exploded", outcome.results[1].message)
  end)

  it("reports the exit code of a worker that said nothing at all", function()
    local item = item_of(ONE_TEST)
    vim.fn.writefile({ "os.exit(3)" }, item.file)

    local outcome = launch(item)

    assert.equal("worker exited with code 3", outcome.results[1].message)
  end)

  it("reports the load error of a spec the worker could not load", function()
    local item = item_of(ONE_TEST)
    vim.fn.writefile({ "this is not lua" }, item.file)

    local outcome = launch(item)

    assert.equal("error", outcome.results[1].status)
    assert.match("temp_spec%.lua", outcome.results[1].message)
  end)

  it("kills a worker that will not finish and reports how long it was given", function()
    local outcome = launch(item_of(NEVER_FINISHES), { timeout = 1000 }, 10000)

    assert.is_true(outcome.timed_out)
    assert.equal("error", outcome.results[1].status)
    assert.equal("worker timed out after 1000ms", outcome.results[1].message)
  end)

  it("gives a worker the item's own timeout ahead of the run's", function()
    local item = item_of(NEVER_FINISHES)
    item.timeout = 500

    local outcome = launch(item, { timeout = 20000 }, 10000)

    assert.equal("worker timed out after 500ms", outcome.results[1].message)
  end)

  it("lets a worker run untimed when the timeout is zero", function()
    local outcome = launch(item_of(ONE_TEST), { timeout = 0 })

    assert.equal("passed", outcome.results[1].status)
    assert.is_nil(outcome.timed_out)
  end)
end)

describe("ntf.core.worker.driver.payload", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("gives a worker a deadline of its own to be killed at", function()
    local payload, timeout = driver.payload(item_of(ONE_TEST), { cwd = helper.root, timeout = 1000 })

    assert.equal(1000, timeout)
    assert.equal(watchdog.deadline(1000), payload.watchdog_ms)
  end)

  it("gives an untimed worker no deadline of its own", function()
    local payload, timeout = driver.payload(item_of(ONE_TEST), { cwd = helper.root, timeout = 0 })

    assert.is_nil(timeout)
    assert.is_nil(payload.watchdog_ms)
  end)
end)

describe("ntf.core.worker.driver.kill_all", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("kills a worker still running, so none of them outlives the run", function()
    local done
    driver.launch(
      item_of(NEVER_FINISHES),
      { root = helper.root, cwd = helper.test_data.full_path, timeout = 0 },
      function(outcome)
        done = outcome
      end
    )

    assert.equal(1, driver.kill_all())

    vim.wait(30000, function()
      return done ~= nil
    end, 20)
    assert(done, "the worker outlived kill_all")
  end)

  it("has nothing left to kill once its workers exited on their own", function()
    launch(item_of(ONE_TEST))

    assert.equal(0, driver.kill_all())
  end)
end)
