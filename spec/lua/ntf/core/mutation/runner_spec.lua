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

local function teardown()
  driver.kill_all()
  helper.after_each()
end

--- @return table # one NtfMutantTask, its only trial the sleeping test
local function sleeping_task()
  local path = helper.test_data:create_file("lua/mod.lua", MODULE)
  local mutant = vim.tbl_extend("force", operators.enumerate(MODULE)[1], { path = vim.fs.normalize(path) })
  return { mutant = mutant, trials = { { item = work.plan({ helper.write_spec(SLEEPS) })[1], baseline_ms = 0 } } }
end

describe("ntf.core.mutation.runner.run", function()
  before_each(helper.before_each)
  after_each(teardown)

  it(
    "gives up on a scoring pass that outlasts its budget, naming the mutants a worker still holds and leaving the launcher's frames out of it",
    function()
      local ok, err = xpcall(function()
        return runner.run({ sleeping_task() }, {
          root = helper.root,
          cwd = helper.test_data.full_path,
          jobs = 1,
          timeout = 30000,
          budget = 300,
        })
      end, debug.traceback)

      assert.is_false(ok)
      local message = report.error_message(err)
      assert.match("^the run gave up after %d+%.%ds: 1 of 1 mutants never reported back", message)
      assert.match("1 of them from a worker it had launched:\n  lua/mod%.lua:%d+:%d+:swap%-boolean", message)
      assert.no.match("stack traceback", message)
    end
  )
end)
