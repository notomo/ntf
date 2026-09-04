local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local runner = require("ntf.core.mutation.runner")
local operators = require("ntf.core.mutation.operators")
local work = require("ntf.core.controller.work")
local driver = require("ntf.core.worker.driver")
local tree = require("ntf.core.tree")
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

local SLEEPS_THEN_DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("sleeps past every budget below", function()
    vim.uv.sleep(3000)
  end)
  ntf.it("detects", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
end)
]]

local DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("passes", function() end)
  ntf.it("passes too", function() end)
  ntf.it("passes as well", function() end)
  ntf.it("detects", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
end)
]]

-- WHY: the leaks a shared process really carries look like this one: a test
-- asserting that a global it does not own is unset, which any test setting it
-- before makes fail whatever the mutant did.
-- NOT: a test that fails on its own too, which the confirming run would agree
-- with and so tell nothing about sharing.
local POISONS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("leaves a global behind", function()
    require("mod")
    vim.g.ntf_runner_spec = "left"
  end)
  ntf.it("wants the global unset", function()
    assert(vim.g.ntf_runner_spec == nil, "a test before it left the global set")
  end)
  ntf.it("detects", function()
    assert(require("mod").answer(), "answer() came back false")
  end)
end)
]]

-- WHY: the other half of what a shared process does: a test passing on what an
-- earlier one left behind, which hides the detection it would make alone.
-- NOT: only the failing half, which the confirming run already answers.
local HIDES = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("leaves a global behind", function()
    require("mod")
    vim.g.ntf_runner_spec = "set"
  end)
  ntf.it("wants the global set", function()
    require("mod")
    assert(vim.g.ntf_runner_spec == "set", "no test before it left the global set")
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

local PROCESS_HOOK = [[
return {
  setup = function()
    local file = io.open("processes.txt", "a")
    file:write("x\n")
    file:close()
  end,
}
]]

local LOADS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("loads the module", function()
    require("mod")
  end)
  ntf.it("passes", function() end)
end)
]]

local TEARDOWN_RAISES = [[return { teardown = function() error("teardown raised") end }]]

--- @param count integer tests to declare
--- @param name_chars integer characters of name each of them carries, which is what fills a batch
--- @return string # a spec whose last test is the one that detects the mutant
local function wide_spec(count, name_chars)
  local lines = { 'local ntf = require("ntf")', 'ntf.describe("x", function()' }
  for index = 1, count do
    local body = index == count and 'assert(require("mod").answer(), "answer() came back false")' or ""
    table.insert(lines, ('  ntf.it("t%d%s", function() %s end)'):format(index, ("n"):rep(name_chars), body))
  end
  table.insert(lines, "end)")
  return table.concat(lines, "\n")
end

local function teardown()
  driver.kill_all()
  helper.after_each()
end

--- @param source string the spec whose every leaf becomes a trial, in the order it declares them
--- @return table # one NtfMutantTask over a mutated module the spec can `require`
--- @return string # the mutated module, as a run in the plugin root writes it
local function task_of(source)
  local path = helper.test_data:create_file("lua/mod.lua", MODULE)
  local mutant = vim.tbl_extend("force", operators.enumerate(MODULE)[1], { path = vim.fs.normalize(path) })
  local trials = vim.tbl_map(function(item)
    return { item = item, baseline_ms = 0 }
  end, work.plan({ helper.write_spec(source) }))
  return { mutant = mutant, trials = trials }, assert(vim.fs.relpath(helper.root, path))
end

--- @param task table one NtfMutantTask
--- @param opts table? run options merged over the defaults
--- @return table # its NtfMutantOutcome
--- @return string[] # the test of every batch a kill was taken back from
local function run(task, opts)
  local restarts = {}
  local outcomes = runner.run(
    { task },
    vim.tbl_extend("force", {
      root = helper.root,
      cwd = helper.test_data.full_path,
      jobs = 1,
      timeout = 30000,
      on_restart = function(trial)
        table.insert(restarts, tree.full_name(trial.item.names))
      end,
    }, opts or {})
  )
  return outcomes[1], restarts
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

  it("takes a batched kill from the test the batch stopped at, in one process for the trials before it", function()
    local outcome = run(task_of(DETECTS), { process_hook = helper.test_data:create_file("hook.lua", PROCESS_HOOK) })

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
    assert.equal(2, process_count())
  end)

  it("takes a batched kill back once the test passes alone, and runs the trials left from a new process", function()
    local outcome, restarts = run((task_of(POISONS)))

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
    assert.equal(1, #restarts)
    assert.equal("x wants the global unset", restarts[1])
  end)

  it("takes a mutant no batch could kill again, with every trial in a process of its own", function()
    local outcome = run((task_of(HIDES)))

    assert.equal("killed", outcome.status)
    assert.equal("x wants the global set", outcome.killed_by)
  end)

  it("gives every trial a process of its own for a task that re-runs a baseline entry", function()
    local task = task_of(DETECTS)
    task.confirm_kill = true

    local outcome = run(task, { process_hook = helper.test_data:create_file("hook.lua", PROCESS_HOOK) })

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
    assert.equal(5, process_count())
  end)

  it("takes the trials a batch was cut short of from where it stopped, not from past the whole batch", function()
    local outcome = run((task_of(FAILS_THEN_DETECTS)))

    assert.equal("killed", outcome.status)
    assert.equal("x detects", outcome.killed_by)
  end)

  it("falls back to the trials a batch stood in for once the batch runs out of its budget", function()
    local outcome = run(task_of(SLEEPS_THEN_DETECTS), { timeout = 300 })

    assert.equal("timeout", outcome.status)
  end)

  it("falls back to the trials a batch stood in for once it fails without naming one of them", function()
    local outcome = run(task_of(LOADS), {
      test_hook = helper.test_data:create_file("test_hook.lua", TEARDOWN_RAISES),
    })

    assert.equal("killed", outcome.status)
    assert.equal("teardown", outcome.killed_by)
  end)

  it("runs the trials one batch has no room left for in the next one", function()
    local outcome = run(task_of(wide_spec(8, 4000)), {
      process_hook = helper.test_data:create_file("hook.lua", PROCESS_HOOK),
    })

    assert.equal("killed", outcome.status)
    assert.match("^x t8n+$", outcome.killed_by)
    assert.equal(4, process_count())
  end)
end)
