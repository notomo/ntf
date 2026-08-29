local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local wait = require("ntf.core.worker.wait")

--- @param f fun()
--- @return number # ms the call took
local function timed(f)
  local before = vim.uv.hrtime()
  f()
  return (vim.uv.hrtime() - before) * 1e-6
end

--- @param state table what the callbacks would have written
--- @return table # one NtfRunState
local function run_state(state)
  return vim.tbl_extend("keep", state, { finished = 0, running = {} })
end

describe("ntf.core.worker.wait.budget_ms", function()
  it("gives a run fifteen minutes on its workers, which no run of a suite spends", function()
    assert.equal(900000, wait.budget_ms)
  end)
end)

describe("ntf.core.worker.wait.settle", function()
  it("returns as soon as the last item reports back, leaving the rest of the budget unspent", function()
    local state = run_state({})
    local budget = 3000
    vim.defer_fn(function()
      state.finished = 2
    end, 10)

    local elapsed_ms = timed(function()
      wait.settle(state, { budget = budget, total = 2, unit = "tests" })
    end)

    assert.is_true(elapsed_ms < budget / 2)
  end)

  it("returns at once for a run with nothing to wait for", function()
    local elapsed_ms = timed(function()
      wait.settle(run_state({}), { budget = 3000, total = 0, unit = "tests" })
    end)

    assert.is_true(elapsed_ms < 1000)
  end)

  it("waits the run budget out for a run that named none of its own", function()
    local state = run_state({})
    vim.defer_fn(function()
      state.finished = 1
    end, 200)

    wait.settle(state, { total = 1, unit = "tests" })

    assert.equal(1, state.finished)
  end)

  it("raises the error a callback reported, leaving the rest of the budget unspent", function()
    local state = run_state({ fatal = "aborted by the callback" })
    local budget = 3000

    local ok, err
    local elapsed_ms = timed(function()
      ok, err = pcall(wait.settle, state, { budget = budget, total = 2, unit = "tests" })
    end)

    assert.is_false(ok)
    assert.equal("aborted by the callback", err)
    assert.is_true(elapsed_ms < budget / 2)
  end)

  it("hands back the items that never reported back once the budget is out", function()
    local state = run_state({ finished = 1 })

    local gave_up = wait.settle(state, { budget = 100, total = 3, unit = "tests" })

    assert.equal(2, gave_up.unfinished)
    assert.equal(3, gave_up.total)
    assert.equal(100, gave_up.budget)
    assert.equal("tests", gave_up.unit)
    assert.same({}, gave_up.launched)
  end)

  it("hands back nothing for a run every item reported back to", function()
    local gave_up = wait.settle(run_state({ finished = 2 }), { budget = 100, total = 2, unit = "tests" })

    assert.is_nil(gave_up)
  end)

  it("gives up on the shortest budget a run can ask for", function()
    local gave_up = wait.settle(run_state({}), { budget = 1, total = 1, unit = "tests" })

    assert.equal(1, gave_up.unfinished)
  end)

  it("names the launched items of the run that gave up, in one order however they were dispatched", function()
    local state = run_state({ running = { "lua/b.lua:1:1:drop-call", "lua/a.lua:2:3:swap-logical" } })

    local gave_up = wait.settle(state, { budget = 100, total = 5, unit = "mutants" })

    assert.same({ "lua/a.lua:2:3:swap-logical", "lua/b.lua:1:1:drop-call" }, gave_up.launched)
  end)
end)

describe("ntf.core.worker.wait.message", function()
  it("says how long the run waited and how much of it never reported back", function()
    local gave_up = { budget = 100, unfinished = 2, total = 3, unit = "tests", launched = {} }

    assert.equal("after 0.1s: 2 of 3 tests never reported back", wait.message(gave_up))
  end)

  it("names the items a worker had been launched for, one to a line", function()
    local gave_up = {
      budget = 900000,
      unfinished = 5,
      total = 5,
      unit = "mutants",
      launched = { "lua/a.lua:2:3:swap-logical", "lua/b.lua:1:1:drop-call" },
    }

    assert.equal(
      "after 900.0s: 5 of 5 mutants never reported back, 2 of them from a worker it had launched:\n"
        .. "  lua/a.lua:2:3:swap-logical\n"
        .. "  lua/b.lua:1:1:drop-call",
      wait.message(gave_up)
    )
  end)
end)
