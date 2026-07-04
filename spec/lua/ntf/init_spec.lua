-- End-to-end tests that launch the real `bin/ntf` (`bin/ntf.bat` on Windows) as
-- a subprocess, exercising the whole CLI path: arg parsing, discovery, planning,
-- parallel worker execution, the rendered report, and the process exit code.
local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local helper = require("ntf.test.helper")

--- Write a spec file under the temp data dir and return its absolute path.
local function spec(name, source)
  return helper.test_data:create_file(name, source)
end

--- Run `bin/ntf` against the given paths plus any extra flags.
local function run(paths, extra_flags)
  local args = vim.list_extend(vim.list_extend({}, extra_flags or {}), paths)
  return helper.run_cli(args)
end

local PASSING = [[
local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert

describe("group", function()
  it("adds", function()
    assert.equal(2, 1 + 1)
  end)
  it("also passes", function()
    assert.is_true(true)
  end)
end)
]]

local FAILING = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("group", function()
  it("explodes", function()
    error("boom")
  end)
end)
]]

local PENDING = [[
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending

describe("group", function()
  it("passes", function() end)
  pending("not yet")
end)
]]

local FILTERABLE = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("group", function()
  it("keep me", function() end)
  it("drop me", function() end)
end)
]]

local LOAD_ERROR = [[
local ntf = require("ntf")
error("top-level boom")
]]

local NOISY = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("group", function()
  it("writes to stdout", function()
    print("from print")
    io.stdout:write("from native write\n")
  end)
end)
]]

local HANGING = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("group", function()
  it("never returns", function()
    while true do end
  end)
end)
]]

describe("bin/ntf end-to-end", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("exits 0 and reports the pass count when every test passes", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path })

    assert.equal(0, obj.code)
    assert.match("2 passed", obj.stdout)
  end)

  it("exits 1 and reports the failure with its message", function()
    local path = spec("fail_spec.lua", FAILING)
    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match("FAIL", obj.stdout)
    assert.match("boom", obj.stdout)
  end)

  it("exits 0 and counts pending declarations", function()
    local path = spec("pending_spec.lua", PENDING)
    local obj = run({ path })

    assert.equal(0, obj.code)
    assert.match("1 pending", obj.stdout)
  end)

  it("runs only leaves matching --filter", function()
    local path = spec("filter_spec.lua", FILTERABLE)
    local obj = run({ path }, { "--filter=keep me" })

    assert.equal(0, obj.code)
    assert.match("1 passed", obj.stdout)
  end)

  it("prints usage and exits 0 with --help", function()
    local obj = helper.run_cli({ "--help" })

    assert.equal(0, obj.code)
    assert.match("Usage: ntf", obj.stdout)
  end)

  it("defaults to ./spec when no path is given", function()
    helper.test_data:create_file("spec/pass_spec.lua", PASSING)
    local obj = helper.run_cli({}, helper.test_data.full_path)

    assert.equal(0, obj.code)
    assert.match("2 passed", obj.stdout)
  end)

  it("exits 2 when no spec path is given and there is no ./spec", function()
    local obj = helper.run_cli({}, helper.test_data.full_path)

    assert.equal(2, obj.code)
    assert.match("no spec paths given", obj.stderr)
  end)

  it("exits 2 on an unknown option", function()
    local obj = helper.run_cli({ "--nope" })

    assert.equal(2, obj.code)
    assert.match("unknown option", obj.stderr)
  end)

  it("exits 2 when a directory contains no spec files", function()
    helper.test_data:create_file("notes.txt", "not a spec")
    local obj = run({ helper.test_data.full_path })

    assert.equal(2, obj.code)
    assert.match("no %*_spec%.lua found", obj.stderr)
  end)

  it("exits 2 with a clean message (no raw trace) when a path does not exist", function()
    local obj = run({ "/no/such/path_spec.lua" })

    assert.equal(2, obj.code)
    assert.match("^path not found: /no/such/path_spec%.lua", obj.stderr)
  end)

  it("exits 1 and reports a LOAD ERROR for a spec that throws at load time", function()
    local path = spec("broken_spec.lua", LOAD_ERROR)
    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match("LOAD ERROR", obj.stdout)
    assert.match("top%-level boom", obj.stdout)
  end)

  it("kills a worker that exceeds --timeout and reports it as an error", function()
    local path = spec("hang_spec.lua", HANGING)
    local obj = run({ path }, { "--timeout=300" })

    assert.equal(1, obj.code)
    assert.match("timed out", obj.stdout)
  end)

  it("exits 2 on an invalid --timeout value", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = helper.run_cli({ "--timeout=nope", path })

    assert.equal(2, obj.code)
    assert.match("invalid %-%-timeout value", obj.stderr)
  end)

  it("runs the --hook module's setup before the spec and teardown after it", function()
    local log = vim.fs.joinpath(helper.test_data.full_path, "hook.log")
    local path = spec(
      "hooked_spec.lua",
      ([[
local ntf = require("ntf")
local it = ntf.it
it("passes", function()
  local f = assert(io.open(%q, "a"))
  f:write("test\n")
  f:close()
end)
]]):format(log)
    )
    local hook = spec(
      "hook.lua",
      ([[
local function append(line)
  local f = assert(io.open(%q, "a"))
  f:write(line .. "\n")
  f:close()
end
return {
  setup = function() append("setup") end,
  teardown = function() append("teardown") end,
}
]]):format(log)
    )

    local obj = run({ path }, { "--hook=" .. hook })

    assert.equal(0, obj.code)
    assert.same({ "setup", "test", "teardown" }, vim.fn.readfile(log))
  end)

  it("surfaces a --hook teardown error without discarding the worker's results", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("hook.lua", [[return { teardown = function() error("teardown boom") end }]])

    local obj = run({ path }, { "--hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("teardown boom", obj.stdout)
    -- the actual tests still ran and are reported, not dropped on the floor
    assert.match("2 passed", obj.stdout)
  end)

  it("surfaces an error from the --hook module's setup as a load error", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("hook.lua", [[return { setup = function() error("setup boom") end }]])

    local obj = run({ path }, { "--hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("setup boom", obj.stdout)
  end)

  it("exits 2 when the --hook module does not exist", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path }, { "--hook=/no/such/hook.lua" })

    assert.equal(2, obj.code)
    assert.match("%-%-hook module not found", obj.stderr)
  end)

  it("runs the --global-hook module's setup and teardown once around the whole run", function()
    local log = vim.fs.joinpath(helper.test_data.full_path, "global_hook.log")
    -- Two top-level tests become two work items (two workers), so a per-worker
    -- hook would log twice; the global hook must still log exactly once.
    local path = spec(
      "global_hooked_spec.lua",
      ([[
local ntf = require("ntf")
local it = ntf.it
local function append(line)
  local f = assert(io.open(%q, "a"))
  f:write(line .. "\n")
  f:close()
end
it("passes", function()
  append("test")
end)
it("also passes", function()
  append("test")
end)
]]):format(log)
    )
    local hook = spec(
      "global_hook.lua",
      ([[
local function append(line)
  local f = assert(io.open(%q, "a"))
  f:write(line .. "\n")
  f:close()
end
return {
  setup = function() append("setup") end,
  teardown = function() append("teardown") end,
}
]]):format(log)
    )

    local obj = run({ path }, { "--global-hook=" .. hook })

    assert.equal(0, obj.code)
    assert.same({ "setup", "test", "test", "teardown" }, vim.fn.readfile(log))
  end)

  it("surfaces a --global-hook teardown error without discarding the results", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("global_hook.lua", [[return { teardown = function() error("teardown boom") end }]])

    local obj = run({ path }, { "--global-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("teardown boom", obj.stderr)
    -- the actual tests still ran and are reported, not dropped on the floor
    assert.match("2 passed", obj.stdout)
  end)

  it("exits 1 when the --global-hook module's setup errors", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("global_hook.lua", [[return { setup = function() error("setup boom") end }]])

    local obj = run({ path }, { "--global-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("setup boom", obj.stderr)
  end)

  it("exits 2 when the --global-hook module does not exist", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path }, { "--global-hook=/no/such/hook.lua" })

    assert.equal(2, obj.code)
    assert.match("%-%-global%-hook module not found", obj.stderr)
  end)

  it("writes a luacov stats file and prints a summary with --coverage", function()
    local path = spec("pass_spec.lua", PASSING)
    -- Keep the stats file inside the temp data dir so teardown cleans it up.
    local stats_file = vim.fs.joinpath(helper.test_data.full_path, "cov.stats.out")
    local obj = run({ path }, { "--coverage=" .. stats_file })

    assert.equal(0, obj.code)
    assert.match("2 passed", obj.stdout)
    assert.match("Coverage:", obj.stdout)
    -- The file exists in luacov format: a "<max>:<path>" header line. (ntf's own
    -- modules run under the spec, so there is always at least one measured file.)
    assert.equal(1, vim.fn.filereadable(stats_file))
    assert.match("^%d+:.+%.lua$", vim.fn.readfile(stats_file)[1])
  end)

  it("counts module-level lines of code required at spec load time", function()
    -- A tiny project: production module under lua/, required at the spec's top
    -- level (so it loads while the tree is built, before any test body runs).
    local root = helper.test_data.full_path
    helper.test_data:create_file(
      "lua/mod/init.lua",
      table.concat({
        "local M = {}",
        "function M.f()",
        "  return 1",
        "end",
        "return M",
      }, "\n")
    )
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'local mod = require("mod")',
        'describe("mod", function()',
        '  it("calls f", function()',
        "    assert.equal(1, mod.f())",
        "  end)",
        "end)",
      }, "\n")
    )
    local stats_file = vim.fs.joinpath(root, "cov.stats.out")

    local obj = helper.run_cli({ "--coverage=" .. stats_file, "spec" }, root)

    assert.equal(0, obj.code)
    -- The module-level line (`local M = {}`, line 1) runs only at require time,
    -- during tree building. It must still be counted, i.e. have a non-zero hit.
    local lines = vim.fn.readfile(stats_file)
    local hits1
    for i, line in ipairs(lines) do
      if line:match("/lua/mod/init%.lua$") then
        hits1 = tonumber(vim.split(lines[i + 1], " ")[1])
      end
    end
    assert.equal(1, hits1)
  end)

  it("captures all of a worker's stdout, including native writes", function()
    local path = spec("noisy_spec.lua", NOISY)
    local obj = run({ path })

    assert.equal(0, obj.code)
    assert.match("OUTPUT", obj.stdout)
    -- both the Lua `print` and the native `io.stdout:write` land in one block,
    -- proving capture no longer depends on swapping `_G.print`/`io.write`.
    assert.match("from print", obj.stdout)
    assert.match("from native write", obj.stdout)
  end)

  it("labels captured output with the test case name", function()
    local path = spec("noisy_spec.lua", NOISY)
    local obj = run({ path })

    assert.equal(0, obj.code)
    assert.match("OUTPUT .* group writes to stdout", obj.stdout)
  end)

  it("discovers and runs every spec file under a directory path", function()
    spec("one_spec.lua", PASSING)
    spec("nested/two_spec.lua", PASSING)
    local obj = run({ helper.test_data.full_path })

    assert.equal(0, obj.code)
    assert.match("4 passed", obj.stdout)
  end)
end)
