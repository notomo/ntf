local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
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

--- @type integer how long the spin lasts, past every wait below so no test sees it end on its own, and short enough that one escaping every kill frees the core it holds
local spin_seconds = 120

local SPINS = ([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("spins", function()
    local deadline = os.time() + %d
    while os.time() < deadline do end
  end)
end)
]]):format(spin_seconds)

-- WHY: this process exits with the leaf it runs, so a worker still going by
-- then is orphaned into a process no run can reach, and holds a core for the
-- rest of its spin.
-- NOT: leaving it to the worker's own deadline, which an untimed launch never
-- sets.
local function teardown()
  driver.kill_all()
  helper.after_each()
end

--- @return integer # timer handles this process holds now
local function timer_count()
  local count = 0
  vim.uv.walk(function(handle)
    if handle:get_type() == "timer" and not handle:is_closing() then
      count = count + 1
    end
  end)
  return count
end

-- WHY: a worker an earlier test launched can close its own timer between the two
-- counts, and only a run that ends holding more of them than it started with
-- kept one of its own open.
-- NOT: an equality, which one of those handles draining fails on its own.
--- @param before integer timer handles this process held before the run
--- @return boolean # whether the run left one behind
local function leaves_a_timer(before)
  return timer_count() > before
end

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
  after_each(teardown)

  it("reports one result for the node it asked for", function()
    local outcome = launch(item_of(ONE_TEST))

    assert.equal(1, #outcome.results)
    assert.equal("passed", outcome.results[1].status)
  end)

  it("runs the --process-hook before the worker loads the spec", function()
    local hook = helper.test_data:create_file(
      "process_hook.lua",
      [[return { setup = function() vim.g.ntf_process_hook_spec = "ran" end }]]
    )
    local item = item_of([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("sees what the process hook set", function()
    ntf.assert.equal("ran", vim.g.ntf_process_hook_spec)
  end)
end)
]])

    local outcome = launch(item, { process_hook = hook })

    assert.equal("passed", outcome.results[1].status)
  end)

  it("errors on a worker whose --process-hook module provides a teardown, which no worker can run either", function()
    local hook =
      helper.test_data:create_file("process_hook.lua", [[return { setup = function() end, teardown = function() end }]])

    local outcome = launch(item_of(ONE_TEST), { process_hook = hook })

    assert.equal("error", outcome.results[1].status)
    assert.match("takes no teardown", outcome.results[1].message)
  end)

  it("refuses a worker whose spec declares another test at the position the run planned", function()
    local item = item_of([[
local ntf = require("ntf")
ntf.describe("g", function()
  if vim.env.NTF_DRIVER_SPEC_GROWS then
    ntf.it("grown", function() end)
  end
  ntf.it("planned", function() end)
end)
]])
    finally(function()
      vim.env.NTF_DRIVER_SPEC_GROWS = nil
    end)
    vim.env.NTF_DRIVER_SPEC_GROWS = "1"

    local outcome = launch(item)

    assert.equal("error", outcome.results[1].status)
    assert.match('the run picked "g planned"', outcome.results[1].message)
    assert.match('this position holds "g grown"', outcome.results[1].message)
  end)

  it("stamps the item's file onto every result, which the worker never sends back itself", function()
    local item = item_of(ONE_TEST)

    local outcome = launch(item)

    assert.equal(item.file, outcome.results[1].file)
  end)

  it("refuses a worker whose spec no longer holds the position the run planned", function()
    local item = item_of(ONE_TEST)
    item.node_id = "a node the rebuilt tree does not hold"

    local outcome = launch(item)

    assert.equal(1, #outcome.results)
    assert.equal("error", outcome.results[1].status)
    assert.match("this position holds no test", outcome.results[1].message)
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

  it("keeps its own result for a test that printed a result block of its own", function()
    local outcome = launch(item_of([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("prints a result block", function()
    print("\n<<<NTF_JSON>>>\n" .. vim.json.encode({ results = {} }) .. "\n<<<END_NTF_JSON>>>\n")
  end)
end)
]]))

    assert.equal(1, #outcome.results)
    assert.equal("passed", outcome.results[1].status)
    assert.match("NTF_JSON", outcome.output.output)
  end)

  it("closes the timeout timer once the worker is done, leaving none behind", function()
    local before = timer_count()

    launch(item_of(ONE_TEST), { timeout = 30000 })

    assert.is_false(leaves_a_timer(before))
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

  it("keeps the load error of a spec that also wrote noise to stderr, which stays captured output", function()
    local item = item_of(ONE_TEST)
    vim.fn.writefile({ 'io.stderr:write("stderr noise")', 'error("the real load failure")' }, item.file)

    local outcome = launch(item)

    assert.equal("error", outcome.results[1].status)
    assert.match("the real load failure", outcome.results[1].message)
    assert.no.match("stderr noise", outcome.results[1].message)
    assert.match("stderr noise", outcome.output.output)
  end)

  it("kills a worker that will not finish and reports its budget and the cleanup the kill skipped", function()
    local outcome = launch(item_of(SPINS), { timeout = 1000 }, 10000)

    assert.is_true(outcome.timed_out)
    assert.equal("error", outcome.results[1].status)
    assert.equal(
      "worker timed out after 1000ms and was killed, so after_each, finally and --test-hook teardown did not run",
      outcome.results[1].message
    )
  end)

  it("gives a worker the item's own timeout ahead of the run's", function()
    local item = item_of(SPINS)
    item.timeout = 500

    local outcome = launch(item, { timeout = 20000 }, 10000)

    assert.equal(
      "worker timed out after 500ms and was killed, so after_each, finally and --test-hook teardown did not run",
      outcome.results[1].message
    )
  end)

  it("runs a worker with no swap file, which several in one directory would collide over", function()
    local outcome = launch(item_of([[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("keeps no swap file", function()
    ntf.assert.is_false(vim.o.swapfile)
  end)
end)
]]))

    assert.equal("passed", outcome.results[1].status)
  end)

  it("lets a worker run untimed when the timeout is zero", function()
    local outcome = launch(item_of(ONE_TEST), { timeout = 0 })

    assert.equal("passed", outcome.results[1].status)
    assert.is_nil(outcome.timed_out)
  end)
end)

describe("ntf.core.worker.driver.payload", function()
  before_each(helper.before_each)
  after_each(teardown)

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

  it("gives a worker the timeout its caller computed ahead of the item's own", function()
    local item = item_of(ONE_TEST)
    item.timeout = 20000

    local payload, timeout = driver.payload(item, { cwd = helper.root, timeout = 30000, timeout_override = 1000 })

    assert.equal(1000, timeout)
    assert.equal(watchdog.deadline(1000), payload.watchdog_ms)
  end)

  it("hands a worker what the run planned at the position it asks for", function()
    local item = item_of(ONE_TEST)

    local payload = driver.payload(item, { cwd = helper.root })

    assert.same(item.names, payload.leaf.names)
    assert.equal(1, payload.leaf.leaves_count)
  end)

  it("gives each worker a marker nonce of its own", function()
    local item = item_of(ONE_TEST)

    local payload = driver.payload(item, { cwd = helper.root })
    local other = driver.payload(item, { cwd = helper.root })

    assert.is_true(payload.nonce ~= other.nonce)
  end)
end)

local MODULE = table.concat({
  "local M = {}",
  "function M.answer()",
  "  return true",
  "end",
  "return M",
}, "\n")

local DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("detects", function()
    ntf.assert.is_true(require("mod").answer())
  end)
end)
]]

local SLEEPS_LONG = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("sleeps past every budget below", function()
    vim.uv.sleep(30000)
  end)
end)
]]

local PROCESS_HOOK_RAISES = [[
return {
  setup = function()
    error("the process hook raised")
  end,
}
]]

--- @param name_chars integer characters of comment the mutant carries, which is what fills a payload
--- @return table # one NtfWorkerMutation over a module the specs below can `require`
local function mutation_of(name_chars)
  local path = helper.test_data:create_file("lua/mod.lua", MODULE)
  local at = assert(MODULE:find("true", 1, true))
  return {
    path = vim.fs.normalize(path),
    start_byte = at - 1,
    end_byte = at + #"true" - 1,
    original = "true",
    replacement = ("false --[[%s]]"):format(("n"):rep(name_chars)),
  }
end

--- @param source string the spec whose every leaf becomes a trial
--- @param budget_ms integer what each of them is given before the run kills the worker
--- @return table[] # the NtfWorkerTrial of each of them
local function trials_of(source, budget_ms)
  return vim.tbl_map(function(item)
    return {
      file = item.file,
      node_id = item.node_id,
      names = item.names,
      leaves_count = item.leaves_count,
      budget_ms = budget_ms,
    }
  end, work.plan({ helper.write_spec(source) }))
end

--- @param jobs table[] the NtfWorkerMutantJob to hand one worker
--- @param opts table? launch options merged over the defaults
--- @return table[] # the NtfWorkerEvent the worker wrote, in order
--- @return table # the NtfWorkerMutantsExit it came to
local function launch_mutants(jobs, opts)
  local events = {} --- @type table[]
  local exit
  driver.launch_mutants(
    jobs,
    vim.tbl_extend("force", { root = helper.root, cwd = helper.test_data.full_path }, opts or {}),
    {
      on_event = function(event)
        table.insert(events, event)
      end,
      on_exit = function(came_to)
        exit = came_to
      end,
    }
  )
  vim.wait(30000, function()
    return exit ~= nil
  end, 20)
  return events, assert(exit, "the worker did not exit")
end

describe("ntf.core.worker.driver.launch_mutants", function()
  before_each(helper.before_each)
  after_each(teardown)

  it("reports a verdict for every mutant one worker is given", function()
    local mutation = mutation_of(0)
    local trials = trials_of(DETECTS, 30000)

    local events, exit = launch_mutants({
      { index = 7, mutation = mutation, trials = trials },
      { index = 9, mutation = mutation, trials = trials },
    })

    local verdicts = vim.tbl_filter(function(event)
      return event.type == "verdict"
    end, events)
    assert.equal(2, #verdicts)
    assert.equal(7, verdicts[1].index)
    assert.equal("killed", verdicts[1].status)
    assert.equal("x detects", verdicts[1].killed_by)
    assert.equal(9, verdicts[2].index)
    assert.is_nil(exit.pending)
  end)

  it("kills a worker that outlasts the budget of the trial it began, naming the mutant it was on", function()
    local events, exit = launch_mutants({
      { index = 4, mutation = mutation_of(0), trials = trials_of(SLEEPS_LONG, 300) },
    })

    assert.is_true(exit.timed_out)
    assert.equal(4, exit.pending)
    assert.equal("begin", events[1].type)
  end)

  it("answers for a worker that reported no verdict with what it exited on", function()
    local hook = helper.test_data:create_file("hook.lua", PROCESS_HOOK_RAISES)

    local _, exit = launch_mutants({
      { index = 1, mutation = mutation_of(0), trials = trials_of(DETECTS, 30000) },
    }, { process_hook = hook })

    assert.is_nil(exit.pending)
    assert.match("the process hook raised", exit.message)
  end)

  it("holds a worker of its own until it exits, so kill_all reaches it", function()
    driver.launch_mutants({
      { index = 1, mutation = mutation_of(0), trials = trials_of(SLEEPS_LONG, 30000) },
    }, { root = helper.root, cwd = helper.test_data.full_path }, {
      on_event = function() end,
      on_exit = function() end,
    })

    assert.equal(1, driver.kill_all())
  end)

  it("lets go of a worker that exited on its own, and of the timer that watched it", function()
    local before = timer_count()

    launch_mutants({ { index = 1, mutation = mutation_of(0), trials = trials_of(DETECTS, 30000) } })

    assert.equal(0, driver.kill_all())
    assert.is_false(leaves_a_timer(before))
  end)

  it("carries a chunk of mutants no environment block would hold", function()
    -- WHY: Windows caps a process environment block at 32767 characters and
    -- spawns nothing at all past it, so the chunk a worker is given reaches it
    -- through a file rather than its environment.
    -- NOT: a payload this size in the environment, which never gets to run.
    local mutation = mutation_of(64 * 1024)

    local events = launch_mutants({ { index = 1, mutation = mutation, trials = trials_of(DETECTS, 30000) } })

    assert.equal("verdict", events[#events].type)
    assert.equal("killed", events[#events].status)
  end)
end)

describe("ntf.core.worker.driver.kill_all", function()
  before_each(helper.before_each)
  after_each(teardown)

  it("kills a worker still running, so none of them outlives the run", function()
    local done
    driver.launch(
      item_of(SPINS),
      { root = helper.root, cwd = helper.test_data.full_path, timeout = 0 },
      function(outcome)
        done = outcome
      end
    )

    assert.equal(1, driver.kill_all())

    assert(done, "kill_all came back before the worker it signalled had exited")
    assert.equal(0, driver.kill_all())
  end)

  it("has nothing left to kill once its workers exited on their own", function()
    launch(item_of(ONE_TEST))

    assert.equal(0, driver.kill_all())
  end)
end)
