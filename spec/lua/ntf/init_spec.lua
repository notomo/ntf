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

  it("runs the --setup script in each worker before any spec", function()
    local path = spec("pass_spec.lua", PASSING)
    local marker = vim.fs.joinpath(helper.test_data.full_path, "injected.marker")
    local setup = spec(
      "setup.lua",
      ([[
local f = assert(io.open(%q, "w"))
f:write("ok")
f:close()
]]):format(marker)
    )

    local obj = run({ path }, { "--setup=" .. setup })

    assert.equal(0, obj.code)
    assert.equal(1, vim.fn.filereadable(marker))
  end)

  it("surfaces an error from the --setup script as a load error", function()
    local path = spec("pass_spec.lua", PASSING)
    local setup = spec("setup.lua", [[error("setup boom")]])

    local obj = run({ path }, { "--setup=" .. setup })

    assert.equal(1, obj.code)
    assert.match("setup boom", obj.stdout)
  end)

  it("exits 2 when the --setup script does not exist", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path }, { "--setup=/no/such/setup.lua" })

    assert.equal(2, obj.code)
    assert.match("%-%-setup script not found", obj.stderr)
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
    assert.match("OUTPUT group writes to stdout", obj.stdout)
  end)

  it("discovers and runs every spec file under a directory path", function()
    spec("one_spec.lua", PASSING)
    spec("nested/two_spec.lua", PASSING)
    local obj = run({ helper.test_data.full_path })

    assert.equal(0, obj.code)
    assert.match("4 passed", obj.stdout)
  end)
end)
