local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local runner = require("ntf.core.mutation.runner")
local operators = require("ntf.core.mutation.operators")
local work = require("ntf.core.controller.work")
local driver = require("ntf.core.worker.driver")
local report = require("ntf.core.controller.report")
local helper = require("ntf.test.helper")

local MODULE = table.concat({
  "local M = {}",
  "function M.answer()",
  "  return true",
  "end",
  "return M",
}, "\n")

local SLEEPS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("sleeps past every budget below", function()
    vim.uv.sleep(3000)
  end)
end)
]]

local DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("passes", function() end)
  ntf.it("passes too", function() end)
  ntf.it("detects", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
  ntf.it("detects as well", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
end)
]]

local FAILS_THEN_DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("fails for its own reasons, before the module is ever loaded", function()
    error("unrelated to the mutant")
  end)
  ntf.it("detects", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
end)
]]

-- WHY: a test that fails once and passes when it is run again is what a kill
-- taken from a shared process looks like when the failure was not the mutant's
-- doing, and the process the trials share is what makes the second run differ.
-- NOT: a test that fails every time, which is the detection this has to be told
-- apart from.
local FAILS_ONCE_THEN_DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("fails until something in the process has run it once", function()
    require("mod")
    local first = vim.g.ntf_runner_spec == nil
    vim.g.ntf_runner_spec = "ran"
    assert(not first, "it was the first run in this process")
  end)
  ntf.it("detects", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
end)
]]

local NOTICES_NOTHING = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("loads the module and asks it nothing", function()
    require("mod")
  end)
end)
]]

local LOADS_NOTHING = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("never reaches the module", function() end)
end)
]]

local CRASHES = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("takes the process with it", function()
    require("mod")
    os.exit(1)
  end)
end)
]]

local PROCESS_HOOK = [[
return {
  setup = function()
    local file = io.open("processes.txt", "a")
    file:write("x\n")
    file:close()
  end,
}
]]

local PROCESS_HOOK_RAISES = [[return { setup = function() error("the process hook raised") end }]]

local TEARDOWN_RAISES = [[return { teardown = function() error("teardown raised") end }]]

local function teardown()
  driver.kill_all()
  helper.after_each()
end

--- @param source string the spec whose every leaf becomes a trial, in the order it declares them
--- @param spec_name string? what to file the spec under, for a run given more than one task
--- @return table # one NtfMutantTask over a mutated module the spec can `require`
--- @return string # the mutated module, as a run in the plugin root writes it
local function task_of(source, spec_name)
  local path = helper.test_data:create_file("lua/mod.lua", MODULE)
  local mutant = vim.tbl_extend("force", operators.enumerate(MODULE)[1], { path = vim.fs.normalize(path) })
  local spec = helper.test_data:create_file(spec_name or "temp_spec.lua", source)
  local trials = vim.tbl_map(function(item)
    return { item = item, baseline_ms = 0 }
  end, work.plan({ spec }))
  return { mutant = mutant, trials = trials }, assert(vim.fs.relpath(helper.root, path))
end

--- @param tasks table[] the NtfMutantTask to run
--- @param opts table? run options merged over the defaults
--- @return table[] # their NtfMutantOutcome, parallel to tasks
--- @return string[] # the test of every kill that was taken back
local function run_all(tasks, opts)
  local retries = {}
  local outcomes = runner.run(
    tasks,
    vim.tbl_extend("force", {
      root = helper.root,
      cwd = helper.test_data.full_path,
      jobs = 1,
      timeout = 30000,
      on_retry = function(name)
        table.insert(retries, name)
      end,
    }, opts or {})
  )
  return outcomes, retries
end

--- @param task table one NtfMutantTask
--- @param opts table? run options merged over the defaults
--- @return table # its NtfMutantOutcome
--- @return string[] # the test of every kill that was taken back
local function run(task, opts)
  local outcomes, retries = run_all({ task }, opts)
  return outcomes[1], retries
end

--- @return integer # how many worker processes the run started, told by the --process-hook every one of them runs
local function process_count()
  local file = io.open(helper.test_data:path("processes.txt"), "r")
  if not file then
    return 0
  end
  local blob = file:read("*a")
  file:close()
  return select(2, blob:gsub("\n", "\n"))
end

describe("ntf.core.mutation.runner.run", function()
  before_each(helper.before_each)
  after_each(teardown)

  it(
    "gives up on a scoring pass that outlasts its budget, naming the mutants a worker still holds and leaving the launcher's frames out of it",
    function()
      local task, mutant_path = task_of(SLEEPS)

      local ok, err = xpcall(function()
        return runner.run({ task }, {
          root = helper.root,
          -- WHY: giving up SIGKILLs a worker that dies after the run returns,
          -- and Windows keeps a directory open for as long as a process has it
          -- as its cwd, so a worker launched in the data dir still holds it
          -- when the teardown deletes it.
          -- NOT: helper.test_data.full_path, where the mutant and its trial
          -- spec sit.
          cwd = helper.root,
          jobs = 1,
          timeout = 30000,
          budget = 300,
        })
      end, debug.traceback)

      assert.is_false(ok)
      local message = report.error_message(err)
      assert.match("^the run gave up after %d+%.%ds: 1 of 1 mutants never reported back", message)
      assert.match(
        ("1 of them from a worker it had launched:\n  %s:%%d+:%%d+:swap%%-boolean"):format(vim.pesc(mutant_path)),
        message
      )
      assert.no.match("stack traceback", message)
    end
  )

  it("takes the kill from the first trial that fails on the mutant, in one process for the trials before it", function()
    local outcome = run(task_of(DETECTS), { process_hook = helper.test_data:create_file("hook.lua", PROCESS_HOOK) })

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
    assert.equal(1, process_count())
  end)

  it("passes over a trial that failed before anything had loaded the mutated source", function()
    local outcome = run((task_of(FAILS_THEN_DETECTS)))

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
  end)

  it("takes a kill back from a test that does not fail a second time, and goes on to the trials after it", function()
    local outcome, retries = run((task_of(FAILS_ONCE_THEN_DETECTS)))

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
    assert.same({ "x fails until something in the process has run it once" }, retries)
  end)

  it("reports a mutant every trial ran through as survived", function()
    local outcome = run((task_of(NOTICES_NOTHING)))

    assert.equal("survived", outcome.status)
    assert.is_nil(outcome.killed_by)
  end)

  it("reports a mutant no trial loaded the source of as not applied", function()
    local outcome = run((task_of(LOADS_NOTHING)))

    assert.equal("not_applied", outcome.status)
  end)

  it("takes a kill from a --test-hook teardown that raises, which no test of the run answers for", function()
    local outcome = run(task_of(NOTICES_NOTHING), {
      test_hook = helper.test_data:create_file("test_hook.lua", TEARDOWN_RAISES),
    })

    assert.equal("killed", outcome.status)
    assert.equal("teardown", outcome.killed_by)
  end)

  it("counts a mutant that hangs a test as a timeout, and judges the mutants after it from a new worker", function()
    local hangs = task_of(SLEEPS, "hangs_spec.lua")
    local detects = task_of(DETECTS, "detects_spec.lua")

    local outcomes = run_all({ hangs, detects }, { timeout = 300 })

    assert.equal("timeout", outcomes[1].status)
    assert.equal("killed", outcomes[2].status)
  end)

  it("takes a kill from the mutant a worker died on, so a crash is not read as a survival", function()
    local outcome = run((task_of(CRASHES)))

    assert.equal("killed", outcome.status)
    assert.equal("x takes the process with it", outcome.killed_by)
  end)

  it("gives every mutant a verdict where there are more of them than one worker takes", function()
    local task = task_of(DETECTS)
    local tasks = {}
    for _ = 1, 70 do
      table.insert(tasks, task)
    end

    local outcomes = run_all(tasks)

    assert.equal(70, #outcomes)
    for _, outcome in ipairs(outcomes) do
      assert.equal("killed", outcome.status)
    end
  end)

  it(
    "fails the run over a worker that reported nothing at all, rather than launching another for its mutants",
    function()
      local ok, err = xpcall(function()
        return run(task_of(DETECTS), {
          process_hook = helper.test_data:create_file("hook.lua", PROCESS_HOOK_RAISES),
        })
      end, debug.traceback)

      assert.is_false(ok)
      local message = report.error_message(err)
      assert.match("a mutation worker reported nothing", message)
      assert.match("the process hook raised", message)
    end
  )
end)
