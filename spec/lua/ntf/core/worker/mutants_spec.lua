local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local mutants = require("ntf.core.worker.mutants")
local protocol = require("ntf.core.worker.protocol")
local operators = require("ntf.core.mutation.operators")
local work = require("ntf.core.controller.work")
local helper = require("ntf.test.helper")

local NONCE = "0123456789abcdef0123456789abcdef"

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
  ntf.it("passes", function() end)
  ntf.it("detects", function()
    ntf.assert.is_true(require("mod").answer())
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

local FAILS_ONCE_THEN_DETECTS = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("fails until something in the process has run it once", function()
    require("mod")
    local first = vim.g.ntf_mutants_spec == nil
    vim.g.ntf_mutants_spec = "ran"
    assert(not first, "it was the first run in this process")
  end)
  ntf.it("detects", function()
    ntf.assert.is_true(require("mod").answer())
  end)
end)
]]

local LEAVES_A_MODULE_LOADED = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("loads a module of its own", function()
    require("leftover")
    require("mod")
  end)
end)
]]

local LOADS_TWICE = [[
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("loads the module", function()
    require("mod")
  end)
  ntf.it("loads it too", function()
    require("mod")
  end)
end)
]]

local COUNTS_LOADS = [[
local source = debug.getinfo(1, "S").source:sub(2)
local file = io.open(vim.fs.joinpath(vim.fs.dirname(source), "loads.txt"), "a")
file:write("x\n")
file:close()
local ntf = require("ntf")
ntf.describe("x", function()
  ntf.it("passes", function()
    require("mod")
  end)
  ntf.it("passes too", function()
    require("mod")
  end)
end)
]]

local NOOP_HOOK = {
  setup = function() end,
  teardown = function() end,
}

--- @param name string what to file the spec under
--- @param source string
--- @return table # the NtfWorkerMutantJob mutation over a module the spec can `require`
--- @return table[] # its NtfWorkerTrial, one per leaf the spec declares
local function job_parts(name, source)
  local path = helper.test_data:create_file("lua/mod.lua", MODULE)
  local site = operators.enumerate(MODULE)[1]
  local mutation = {
    path = vim.fs.normalize(path),
    start_byte = site.start_byte,
    end_byte = site.end_byte,
    original = site.original,
    replacement = site.replacement,
  }
  local trials = vim.tbl_map(function(item)
    return {
      file = item.file,
      node_id = item.node_id,
      names = item.names,
      leaves_count = item.leaves_count,
      budget_ms = 30000,
    }
  end, work.plan({ helper.test_data:create_file(name, source) }))
  return mutation, trials
end

--- @param name string what to file the spec under
--- @param source string
--- @param index integer? the task the job answers as (default 1)
--- @return table # one NtfWorkerMutantJob
local function job_of(name, source, index)
  local mutation, trials = job_parts(name, source)
  return { index = index or 1, mutation = mutation, trials = trials }
end

--- @param jobs table[] the NtfWorkerMutantJob to take
--- @param hook table? the NtfHook bracketing every trial (default: one that does nothing)
--- @return table[] # the NtfWorkerEvent written for them
local function run(jobs, hook)
  local written = {}
  local saved = io.stdout
  finally(function()
    io.stdout = saved
    package.loaded["mod"] = nil
  end)
  io.stdout = {
    write = function(_, text)
      table.insert(written, text)
    end,
    flush = function() end,
  }
  mutants.run({ mutants = jobs, cwd = helper.test_data.full_path, nonce = NONCE }, hook or NOOP_HOOK)
  io.stdout = saved
  return protocol.event_reader(NONCE)(table.concat(written))
end

--- @param events table[] the NtfWorkerEvent of a run
--- @param index integer? the task to take the verdict of (default 1)
--- @return table # the verdict event for it
local function verdict_of(events, index)
  for _, event in ipairs(events) do
    if event.type == "verdict" and event.index == (index or 1) then
      return event
    end
  end
  error("no verdict for task " .. tostring(index or 1))
end

describe("ntf.core.worker.mutants.reset_point", function()
  it("drops what was loaded after it and leaves what the process already held", function()
    package.loaded["ntf_mutants_spec_held"] = { held = true }
    finally(function()
      package.loaded["ntf_mutants_spec_held"] = nil
      package.loaded["ntf_mutants_spec_later"] = nil
    end)

    local reset = mutants.reset_point()
    package.loaded["ntf_mutants_spec_later"] = { later = true }
    reset()

    assert.is_nil(package.loaded["ntf_mutants_spec_later"])
    assert.is_true(package.loaded["ntf_mutants_spec_held"].held)
  end)

  it("gives back a module a trial dropped, which the process itself is reached through", function()
    package.loaded["ntf_mutants_spec_held"] = { held = true }
    finally(function()
      package.loaded["ntf_mutants_spec_held"] = nil
    end)

    local reset = mutants.reset_point()
    package.loaded["ntf_mutants_spec_held"] = nil
    reset()

    assert.is_true(package.loaded["ntf_mutants_spec_held"].held)
  end)

  it("takes back the loaders and the loadfile a trial installed, which the next mutant is served through", function()
    local loaders_before = vim.list_slice(package.loaders)
    local loadfile_before = _G.loadfile
    local dofile_before = _G.dofile
    finally(function()
      _G.loadfile = loadfile_before
      _G.dofile = dofile_before
    end)

    local reset = mutants.reset_point()
    table.insert(package.loaders, 2, function() end)
    _G.loadfile = function() end
    _G.dofile = function() end
    reset()

    assert.same(loaders_before, package.loaders)
    assert.equal(loadfile_before, _G.loadfile)
    assert.equal(dofile_before, _G.dofile)
  end)
end)

describe("ntf.core.worker.mutants.run", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("takes a kill from the first trial that fails on the mutant, naming that test", function()
    local events = run({ job_of("detects_spec.lua", DETECTS) })

    local verdict = verdict_of(events)
    assert.equal("killed", verdict.status)
    assert.equal("x detects", verdict.killed_by)
    assert.is_nil(verdict.retried)
    assert.same(
      { "begin", "begin", "begin", "verdict" },
      vim.tbl_map(function(event)
        return event.type
      end, events)
    )
  end)

  it("says a mutant every trial ran through survived", function()
    local verdict = verdict_of(run({ job_of("passes_spec.lua", NOTICES_NOTHING) }))

    assert.equal("survived", verdict.status)
    assert.is_nil(verdict.killed_by)
  end)

  it("says a mutant no trial loaded the source of was not applied", function()
    local verdict = verdict_of(run({ job_of("unloading_spec.lua", LOADS_NOTHING) }))

    assert.equal("not_applied", verdict.status)
  end)

  it("takes a kill back from a test that does not fail a second time, and goes on to the trials after it", function()
    finally(function()
      vim.g.ntf_mutants_spec = nil
    end)

    local verdict = verdict_of(run({ job_of("flaky_spec.lua", FAILS_ONCE_THEN_DETECTS) }))

    assert.equal("killed", verdict.status)
    assert.equal("x detects", verdict.killed_by)
    assert.same({ "x fails until something in the process has run it once" }, verdict.retried)
  end)

  it("takes a kill from a --test-hook teardown that raises, which no test of the run answers for", function()
    local raises = {
      setup = function() end,
      teardown = function()
        error("teardown raised")
      end,
    }

    local verdict = verdict_of(run({ job_of("passes_spec.lua", NOTICES_NOTHING) }, raises))

    assert.equal("killed", verdict.status)
    assert.equal("teardown", verdict.killed_by)
  end)

  it("takes a kill from a --test-hook setup that raises, naming the trial it was to bracket", function()
    local setups = 0
    local raises = {
      setup = function()
        setups = setups + 1
        if setups > 1 then
          error("setup raised")
        end
      end,
      teardown = function() end,
    }

    local verdict = verdict_of(run({ job_of("twice_spec.lua", LOADS_TWICE) }, raises))

    assert.equal("killed", verdict.status)
    assert.equal("x loads it too", verdict.killed_by)
  end)

  it("takes a kill from a trial whose file no longer holds what the run planned there", function()
    local job = job_of("diverged_spec.lua", LOADS_TWICE)
    job.trials[2].names = { "gone" }

    local verdict = verdict_of(run({ job }))

    assert.equal("killed", verdict.status)
    assert.equal("gone", verdict.killed_by)
  end)

  it("loads a spec file once for every trial of it one mutant has", function()
    local job = job_of("counts_spec.lua", COUNTS_LOADS)
    helper.test_data:delete("loads.txt")

    run({ job })

    local file = assert(io.open(helper.test_data:path("loads.txt"), "r"))
    local blob = file:read("*a")
    file:close()
    assert.equal("x\n", blob)
  end)

  it("gives the next mutant a process that holds neither the one before it nor what its trials loaded", function()
    helper.test_data:create_file("lua/leftover.lua", "return {}")
    vim.opt.runtimepath:append(helper.test_data.full_path)
    finally(function()
      vim.opt.runtimepath:remove(helper.test_data.full_path)
      package.loaded["leftover"] = nil
    end)
    local loaders_before = #package.loaders
    local first = job_of("leftover_spec.lua", LEAVES_A_MODULE_LOADED, 1)
    local second = job_of("passes_spec.lua", NOTICES_NOTHING, 2)

    local events = run({ first, second })

    assert.equal("survived", verdict_of(events, 1).status)
    assert.equal("survived", verdict_of(events, 2).status)
    assert.equal(loaders_before, #package.loaders)
    assert.is_nil(package.loaded["mod"])
    assert.is_nil(package.loaded["leftover"])
  end)
end)
