local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local verdict = require("ntf.core.mutation.verdict")

--- @param status string
--- @param name string?
--- @return table # one NtfResult
local function result(status, name)
  return { id = "1.1", status = status, names = { "mod", name or status } }
end

--- @param overrides table?
--- @return table # one NtfWorkerOutcome
local function outcome(overrides)
  return vim.tbl_extend("force", { results = { result("passed") }, mutation_applied = true }, overrides or {})
end

--- @param overrides table?
--- @return table # one NtfMutantProgress
local function progress(overrides)
  return vim.tbl_extend("force", verdict.new_progress(), overrides or {})
end

describe("ntf.core.mutation.verdict.new_progress", function()
  it("starts with nothing applied", function()
    assert.same({ applied = false }, verdict.new_progress())
  end)
end)

describe("ntf.core.mutation.verdict.step", function()
  it("settles a failing trial as killed, naming the test", function()
    local settled = verdict.step(outcome({ results = { result("passed"), result("failed", "adds") } }), progress())

    assert.same({ status = "killed", killed_by = "mod adds" }, settled)
  end)

  it("settles an erroring trial as killed too", function()
    local settled = verdict.step(outcome({ results = { result("error", "blows up") } }), progress())

    assert.same({ status = "killed", killed_by = "mod blows up" }, settled)
  end)

  it("settles a timed-out trial as timeout", function()
    local settled = verdict.step(outcome({ timed_out = true }), progress())

    assert.same({ status = "timeout" }, settled)
  end)

  it("runs the next trial after a clean one, remembering that the mutant was applied", function()
    local settled, next_progress = verdict.step(outcome(), progress())

    assert.is_nil(settled)
    assert.same({ applied = true }, next_progress)
  end)

  it("runs the next trial after one that could not load the mutated source, leaving it unapplied", function()
    local settled, next_progress = verdict.step(outcome({ mutation_applied = false }), progress())

    assert.is_nil(settled)
    assert.same({ applied = false }, next_progress)
  end)

  it("keeps an earlier trial's applied mark through one that could not load the mutated source", function()
    local settled, next_progress = verdict.step(outcome({ mutation_applied = false }), progress({ applied = true }))

    assert.is_nil(settled)
    assert.is_true(next_progress.applied)
  end)

  it("marks the mutant applied on the trial that killed it", function()
    local _, next_progress = verdict.step(outcome({ results = { result("failed", "adds") } }), progress())

    assert.same({ applied = true }, next_progress)
  end)

  it("leaves the caller's progress untouched, so a step never edits what it was handed", function()
    local given = progress()

    verdict.step(outcome({ results = { result("failed", "adds") } }), given)

    assert.same({ applied = false }, given)
  end)
end)

describe("ntf.core.mutation.verdict.exhausted", function()
  it("calls a mutant no trial detected survived", function()
    assert.same({ status = "survived" }, verdict.exhausted(progress({ applied = true })))
  end)

  it("calls a mutant no trial could apply not applied, rather than survived", function()
    assert.same({ status = "not_applied" }, verdict.exhausted(progress()))
  end)
end)
