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

describe("ntf.core.worker.wait.settle", function()
  it("returns as soon as the last item reports back, leaving the rest of the budget unspent", function()
    local state = { finished = 0 }
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
      wait.settle({ finished = 0 }, { budget = 3000, total = 0, unit = "tests" })
    end)

    assert.is_true(elapsed_ms < 1000)
  end)

  it("raises the error a callback reported, leaving the rest of the budget unspent", function()
    local state = { finished = 0, fatal = "aborted by the callback" }
    local budget = 3000

    local ok, err
    local elapsed_ms = timed(function()
      ok, err = pcall(wait.settle, state, { budget = budget, total = 2, unit = "tests" })
    end)

    assert.is_false(ok)
    assert.equal("aborted by the callback", err)
    assert.is_true(elapsed_ms < budget / 2)
  end)

  it("raises with the items that never reported back once the budget is out", function()
    local ok, err = pcall(wait.settle, { finished = 1 }, { budget = 100, total = 3, unit = "tests" })

    assert.is_false(ok)
    assert.equal("the run gave up after 0.1s: 2 of 3 tests never reported back", err)
  end)

  it("names the items of the run that gave up", function()
    local ok, err = pcall(wait.settle, { finished = 0 }, { budget = 100, total = 1, unit = "mutants" })

    assert.is_false(ok)
    assert.equal("the run gave up after 0.1s: 1 of 1 mutants never reported back", err)
  end)
end)

describe("ntf.core.worker.wait.budget", function()
  it("gives a run ten minutes, however many items it waits on", function()
    assert.equal(600000, wait.budget(1))
    assert.equal(600000, wait.budget(1000000))
  end)

  it("keeps that floor for a run whose items earn less than it", function()
    assert.equal(600000, wait.budget(3, 10000))
  end)

  it("grows the budget with the items once they earn more than the floor", function()
    assert.equal(700000, wait.budget(70, 10000))
  end)
end)
