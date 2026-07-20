local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local helper = require("ntf.test.helper")

--- @param name string
--- @param source string
--- @return string # absolute path under the temp data dir
local function spec(name, source)
  return helper.test_data:create_file(name, source)
end

--- @param paths string[]
--- @param extra_flags string[]?
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

local SLOW = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("group", function()
  it("takes its time", function()
    vim.wait(200)
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

  it("exits 2 when an explicitly passed file is not a *_spec.lua", function()
    local path = helper.test_data:create_file("plain.lua", PASSING)
    local obj = run({ path })

    assert.equal(2, obj.code)
    assert.match("^not a %*_spec%.lua file: ", obj.stderr)
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

  it("disables the worker timeout with --timeout=0", function()
    -- 0 must mean "no timer at all": a literal 0ms timer would kill the worker
    -- before this slow-but-finite test could pass.
    local path = spec("slow_spec.lua", SLOW)
    local obj = run({ path }, { "--timeout=0" })

    assert.equal(0, obj.code)
    assert.match("1 passed", obj.stdout)
  end)

  it("records each test's duration in the schedule cache, merging across runs", function()
    spec("pass_spec.lua", PASSING)
    local root = helper.test_data.full_path

    local obj = helper.run_cli({ "pass_spec.lua" }, root)

    assert.equal(0, obj.code)
    local cache_file = vim.fn.glob(helper.test_data:path("xdg_cache") .. "/**/ntf/schedule/*.json")
    local by_name = vim.json.decode(table.concat(vim.fn.readfile(cache_file), "\n")).files["pass_spec.lua"]
    assert.is_true(by_name["group adds"].ms > 0)
    assert.equal("passed", by_name["group adds"].status)
    assert.is_true(by_name["group also passes"].ms > 0)

    local filtered = helper.run_cli({ "--filter=adds", "pass_spec.lua" }, root)

    assert.equal(0, filtered.code)
    by_name = vim.json.decode(table.concat(vim.fn.readfile(cache_file), "\n")).files["pass_spec.lua"]
    assert.is_true(by_name["group adds"].ms > 0)
    assert.is_true(by_name["group also passes"].ms > 0)
  end)

  it("runs the --test-hook module's setup before the spec and teardown after it", function()
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

    local obj = run({ path }, { "--test-hook=" .. hook })

    assert.equal(0, obj.code)
    assert.same({ "setup", "test", "teardown" }, vim.fn.readfile(log))
  end)

  it("surfaces a --test-hook teardown error without discarding the worker's results", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("hook.lua", [[return { teardown = function() error("teardown boom") end }]])

    local obj = run({ path }, { "--test-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("teardown boom", obj.stdout)
    -- the actual tests still ran and are reported, not dropped on the floor
    assert.match("2 passed", obj.stdout)
  end)

  it("surfaces an error from the --test-hook module's setup as a load error", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("hook.lua", [[return { setup = function() error("setup boom") end }]])

    local obj = run({ path }, { "--test-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("setup boom", obj.stdout)
  end)

  it("exits 2 when the --test-hook module does not exist", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path }, { "--test-hook=/no/such/hook.lua" })

    assert.equal(2, obj.code)
    assert.match("%-%-test%-hook module not found", obj.stderr)
  end)

  it("runs the --global-hook module's setup and teardown once around the whole run", function()
    local log = vim.fs.joinpath(helper.test_data.full_path, "global_hook.log")
    -- Two top-level tests become two work items (two workers), so a --test-hook
    -- would log twice; the global hook must still log exactly once. The spec also
    -- logs at its top level, which runs on every load: once when the controller
    -- plans the run and once per worker. Setup must precede even the plan's load.
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
append("load")
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

    local obj = run({ path }, { "--global-hook=" .. hook, "--jobs=1" })

    assert.equal(0, obj.code)
    assert.same({ "setup", "load", "load", "test", "load", "test", "teardown" }, vim.fn.readfile(log))
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
    local lines = vim.fn.readfile(stats_file)
    local hits1
    for i, line in ipairs(lines) do
      if line:match("/lua/mod/init%.lua$") then
        hits1 = tonumber(vim.split(lines[i + 1], " ")[1])
      end
    end
    assert.equal(1, hits1)
  end)

  it("lists a production file no test ever executed at 0%", function()
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
      "lua/mod/unused.lua",
      table.concat({
        "local M = {}",
        "function M.g()",
        "  return 2",
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
    assert.match("lua/mod/unused%.lua%s+0%.0%%", obj.stdout)
  end)

  it("measures nothing under an --exclude-code path", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file(
      "lua/mod/init.lua",
      table.concat({
        "local M = {}",
        "function M.f()",
        "  return require('vendor.dep').g()",
        "end",
        "return M",
      }, "\n")
    )
    -- Excluded although the tests do run it: the point is that it is not the code
    -- under test.
    helper.test_data:create_file(
      "lua/vendor/dep.lua",
      table.concat({
        "local M = {}",
        "function M.g()",
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

    local obj = helper.run_cli({ "--coverage=" .. stats_file, "--exclude-code=lua/vendor", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("lua/mod/init%.lua", obj.stdout)
    assert.no.match("vendor", obj.stdout)
    assert.no.match("vendor", table.concat(vim.fn.readfile(stats_file), "\n"))
  end)

  it("counts every hot-loop iteration; the JIT must not skip the line hook", function()
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
        '  it("calls f in a hot loop", function()',
        "    local total = 0",
        "    for _ = 1, 1000 do",
        "      total = total + mod.f()",
        "    end",
        "    assert.equal(1000, total)",
        "  end)",
        "end)",
      }, "\n")
    )
    local stats_file = vim.fs.joinpath(root, "cov.stats.out")

    local obj = helper.run_cli({ "--coverage=" .. stats_file, "spec" }, root)

    assert.equal(0, obj.code)
    local lines = vim.fn.readfile(stats_file)
    local hits3
    for i, line in ipairs(lines) do
      if line:match("/lua/mod/init%.lua$") then
        hits3 = tonumber(vim.split(lines[i + 1], " ")[3])
      end
    end
    assert.equal(1000, hits3)
  end)

  it("sums per-line hits across workers", function()
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
        '  it("calls f once", function()',
        "    assert.equal(1, mod.f())",
        "  end)",
        '  it("calls f again", function()',
        "    assert.equal(1, mod.f())",
        "  end)",
        "end)",
      }, "\n")
    )
    local stats_file = vim.fs.joinpath(root, "cov.stats.out")

    local obj = helper.run_cli({ "--coverage=" .. stats_file, "spec" }, root)

    assert.equal(0, obj.code)
    local lines = vim.fn.readfile(stats_file)
    local hits3
    for i, line in ipairs(lines) do
      if line:match("/lua/mod/init%.lua$") then
        hits3 = tonumber(vim.split(lines[i + 1], " ")[3])
      end
    end
    assert.equal(2, hits3)
  end)

  it("does not consume a following path as a bare optional-argument flag's value", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'describe("mod", function()',
        '  it("passes", function()',
        "    assert.equal(1, 1)",
        "  end)",
        "end)",
      }, "\n")
    )

    local obj = helper.run_cli({ "--coverage", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("1 passed", obj.stdout)
    assert.equal(1, vim.fn.filereadable(vim.fs.joinpath(root, "luacov.stats.out")))
  end)

  it("captures all of a worker's stdout, including native writes", function()
    local path = spec("noisy_spec.lua", NOISY)
    local obj = run({ path })

    assert.equal(0, obj.code)
    assert.match("OUTPUT", obj.stdout)
    assert.match("from print", obj.stdout)
    assert.match("from native write", obj.stdout)
  end)

  it("labels captured output with the test case name", function()
    local path = spec("noisy_spec.lua", NOISY)
    local obj = run({ path })

    assert.equal(0, obj.code)
    assert.match("OUTPUT .* group writes to stdout", obj.stdout)
  end)

  it("emits no OUTPUT block for a worker that died before reporting", function()
    local path = spec(
      "dying_spec.lua",
      [[
local ntf = require("ntf")
local it = ntf.it
it("dies", function()
  io.stdout:write("noise before death\n")
  os.exit(3)
end)
]]
    )
    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match("ERROR", obj.stdout)
    assert.no.match("OUTPUT", obj.stdout)
  end)

  it("discovers and runs every spec file under a directory path", function()
    spec("one_spec.lua", PASSING)
    spec("nested/two_spec.lua", PASSING)
    local obj = run({ helper.test_data.full_path })

    assert.equal(0, obj.code)
    assert.match("4 passed", obj.stdout)
  end)
end)

local MUTATION_MODULE = table.concat({
  "local M = {}",
  "function M.is_positive(n)",
  "  return n > 0",
  "end",
  "function M.min(a, b)",
  "  if a < b then",
  "    return a",
  "  end",
  "  return b",
  "end",
  "return M",
}, "\n")

local MUTATION_SPEC = table.concat({
  'local ntf = require("ntf")',
  "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
  'local mod = require("mod")',
  'describe("mod", function()',
  '  it("detects positives at the boundary", function()',
  "    assert.is_false(mod.is_positive(0))",
  "    assert.is_true(mod.is_positive(1))",
  "  end)",
  '  it("takes the min", function()',
  "    assert.equal(1, mod.min(1, 2))",
  "  end)",
  "end)",
}, "\n")

--- @return string root, string results_file
local function mutation_project()
  local root = helper.test_data.full_path
  helper.test_data:create_file("lua/mod.lua", MUTATION_MODULE)
  helper.test_data:create_file("spec/mod_spec.lua", MUTATION_SPEC)
  return root, vim.fs.joinpath(root, "ntf-mutation.json")
end

describe("ntf --mutation", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports the mutants a passing suite fails to detect", function()
    local root, results_file = mutation_project()

    local obj = helper.run_cli({ "--mutation", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("2 tests: 2 passed", obj.stdout)
    assert.match("Mutation: %d+%.%d%%", obj.stdout)
    assert.match("SURVIVED lua/mod%.lua:6 swap%-relational: < %-> <=", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.survived)
    assert.equal(0, results.counts.not_applied)
    assert.equal(2, results.counts.killed)
  end)

  it("reports a mutant no test reaches as uncovered", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "--mutation", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("NO COVERAGE lua/dead%.lua:", obj.stdout)
  end)

  it("runs a mutant whose line never receives a hit against the tests covering its statement", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file(
      "lua/config.lua",
      table.concat({
        "return {",
        "  value = 10,",
        "  strict = false,",
        "}",
      }, "\n")
    )
    helper.test_data:create_file(
      "spec/config_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'describe("config", function()',
        '  it("pins the values", function()',
        '    local config = require("config")',
        "    assert.equal(10, config.value)",
        "    assert.is_false(config.strict)",
        "  end)",
        "end)",
      }, "\n")
    )
    local results_file = vim.fs.joinpath(root, "ntf-mutation.json")

    local obj = helper.run_cli({ "--mutation", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("NO COVERAGE", obj.stdout)
    assert.match("Mutation: 100%.0%%", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(2, results.counts.killed)
    assert.equal(0, results.counts.no_coverage)
  end)

  it("mutates only the files under the --mutation path", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "--mutation=lua/mod.lua", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("dead%.lua", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.same({ vim.fs.joinpath(root, "lua/mod.lua") }, vim.tbl_keys(results.files))
  end)

  it("mutates nothing under an --exclude-code path", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/vendor/dep.lua", MUTATION_MODULE)

    local obj =
      helper.run_cli({ "--mutation", "--exclude-code=lua/vendor", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("vendor", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.same({ vim.fs.joinpath(root, "lua/mod.lua") }, vim.tbl_keys(results.files))
  end)

  it("exits non-zero and reports the categories when --mutation-strict finds a survivor", function()
    local root, results_file = mutation_project()

    local obj =
      helper.run_cli({ "--mutation", "--mutation-strict", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation gate failed: 1 survived", obj.stderr)
  end)

  it("exits zero when --mutation-strict gates only a category that is empty", function()
    local root, results_file = mutation_project()

    -- The fixture leaves one survivor and no uncovered mutant, so gating only
    -- no_coverage passes.
    local obj = helper.run_cli(
      { "--mutation", "--mutation-strict=no_coverage", "--mutation-results=" .. results_file, "spec" },
      root
    )

    assert.equal(0, obj.code)
  end)

  it("leaves a mutant listed in --mutation-baseline out of the score as equivalent", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({
        version = 1,
        entries = {
          {
            path = "lua/mod.lua",
            col = 7,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
          },
        },
      })
    )

    local obj = helper.run_cli(
      { "--mutation", "--mutation-baseline=baseline.json", "--mutation-results=" .. results_file, "spec" },
      root
    )

    assert.equal(0, obj.code)
    assert.match("Mutation: 100%.0%%", obj.stdout)
    assert.match("1 equivalent", obj.stdout)
    assert.no.match("SURVIVED", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.equivalent)
    assert.equal(0, results.counts.survived)
  end)

  it("exits non-zero when a --mutation-baseline entry matches nothing", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "baseline.json",
      vim.json.encode({
        version = 1,
        entries = {
          {
            path = "lua/mod.lua",
            col = 7,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a <= b then",
            rationale = "stale: the marked line has changed",
          },
        },
      })
    )

    local obj = helper.run_cli(
      { "--mutation", "--mutation-baseline=baseline.json", "--mutation-results=" .. results_file, "spec" },
      root
    )

    assert.equal(1, obj.code)
    assert.match("LOST BASELINE lua/mod%.lua swap%-relational: < %-> <=", obj.stdout)
    assert.match("1 %-%-mutation%-baseline entry matched no mutant", obj.stderr)
  end)

  it("rejects an invalid --mutation-baseline before running the tests", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("baseline.json", vim.json.encode({ version = 1, entries = { { path = "x" } } }))

    local obj = helper.run_cli(
      { "--mutation", "--mutation-baseline=baseline.json", "--mutation-results=" .. results_file, "spec" },
      root
    )

    assert.equal(2, obj.code)
    assert.match("entries%[1%]", obj.stderr)
    assert.no.match("passed", obj.stdout)
  end)

  it("counts a mutant that hangs the tests as detected", function()
    local root = helper.test_data.full_path
    local results_file = vim.fs.joinpath(root, "ntf-mutation.json")
    -- `i = i + 1` becomes `i = i - 1`, and the loop never ends.
    helper.test_data:create_file(
      "lua/loop.lua",
      table.concat({
        "local M = {}",
        "function M.count(n)",
        "  local i = 0",
        "  while i < n do",
        "    i = i + 1",
        "  end",
        "  return i",
        "end",
        "return M",
      }, "\n")
    )
    helper.test_data:create_file(
      "spec/loop_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        'ntf.it("counts up to n", function()',
        '  ntf.assert.equal(3, require("loop").count(3))',
        "end)",
      }, "\n")
    )

    local obj = helper.run_cli({ "--mutation", "--mutation-results=" .. results_file, "--timeout=1000", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("1 timeout", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.timeout)
  end)

  it("skips the mutation run when the tests fail", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "spec/failing_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        'ntf.it("fails", function()',
        "  ntf.assert.equal(1, 2)",
        "end)",
      }, "\n")
    )

    local obj = helper.run_cli({ "--mutation", "--mutation-results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation run skipped", obj.stderr)
    assert.no.match("Mutation:", obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)
end)

describe("ntf --list", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("lists every test as path:line: full name", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path }, { "--list" })

    assert.equal(0, obj.code)
    assert.match("pass_spec%.lua:%d+: group adds\n", obj.stdout)
    assert.match("pass_spec%.lua:%d+: group also passes\n", obj.stdout)
    assert.no.match("passed", obj.stdout)
  end)

  it("exits 0 for a failing spec because the test bodies never run", function()
    local path = spec("fail_spec.lua", FAILING)
    local obj = run({ path }, { "--list" })

    assert.equal(0, obj.code)
    assert.match("fail_spec%.lua:%d+: group explodes\n", obj.stdout)
    assert.no.match("FAIL", obj.stdout)
  end)

  it("lists only the tests matching --filter", function()
    local path = spec("filter_spec.lua", FILTERABLE)
    local obj = run({ path }, { "--list", "--filter=keep me" })

    assert.equal(0, obj.code)
    assert.match("keep me", obj.stdout)
    assert.no.match("drop me", obj.stdout)
  end)

  it("reports a LOAD ERROR on stderr and exits 1, still listing the loadable tests", function()
    spec("broken_spec.lua", LOAD_ERROR)
    spec("pass_spec.lua", PASSING)
    local obj = run({ helper.test_data.full_path }, { "--list" })

    assert.equal(1, obj.code)
    assert.match("pass_spec%.lua:%d+: group adds\n", obj.stdout)
    assert.match("LOAD ERROR", obj.stderr)
    assert.match("top%-level boom", obj.stderr)
    assert.no.match("LOAD ERROR", obj.stdout)
  end)

  it("runs the tests and lists the mutants with their coverage under --mutation", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "--list", "--mutation", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("spec/mod_spec%.lua:%d+: mod detects positives at the boundary\n", obj.stdout)
    assert.match("lua/mod%.lua:6:%d+: swap%-relational: < %-> <= %(covered by 1 test%)\n", obj.stdout)
    assert.match("lua/dead%.lua:%d+:%d+: [%w-]+: .* %(no coverage%)\n", obj.stdout)
    assert.no.match("Mutation:", obj.stdout)
    assert.no.match("passed", obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)

  it("skips the mutant list when the tests fail", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("spec/fail_spec.lua", FAILING)

    local obj = helper.run_cli({ "--list", "--mutation", "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation list skipped", obj.stderr)
    assert.match("FAIL", obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)
end)
