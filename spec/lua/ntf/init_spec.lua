local ntf = require("ntf")
local describe, before_each, after_each, it, pending, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.pending, ntf.assert
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

--- @param args string[] CLI arguments
--- @return string[] # bin/ntf's own command line, for a run that needs an env helper.run_cli does not set
local function cli(args)
  local is_win = vim.fn.has("win32") == 1
  local script = vim.fs.joinpath(helper.root, "bin", is_win and "ntf.bat" or "ntf")
  local cmd = is_win and { "cmd.exe", "/c", script } or { script }
  return vim.list_extend(cmd, args)
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

  it("exits 2 when --filter matches no test, instead of reporting a run of none", function()
    local path = spec("filter_spec.lua", FILTERABLE)
    local obj = run({ path }, { "--filter=nothing answers to this" })

    assert.equal(2, obj.code)
    assert.match("no test matched %-%-filter: nothing answers to this", obj.stderr)
    assert.no.match("0 tests", obj.stdout)
  end)

  it("exits 2 when the spec files declare no test at all", function()
    local path = spec("empty_spec.lua", "")
    local obj = run({ path })

    assert.equal(2, obj.code)
    assert.match("no test declared in: " .. vim.pesc(path), obj.stderr)
  end)

  it("reports the load errors rather than an empty selection when nothing loaded", function()
    local path = spec("broken_spec.lua", LOAD_ERROR)
    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match("LOAD ERROR", obj.stdout)
    assert.no.match("no test declared", obj.stderr)
  end)

  it("prints usage and exits 0 with --help", function()
    local obj = helper.run_cli({ "--help" })

    assert.equal(0, obj.code)
    assert.match("Usage: ntf", obj.stdout)
  end)

  it("finds the plugin through a symlink to bin/ntf, as an install on $PATH is", function()
    if vim.fn.has("win32") == 1 then
      return pending("windows runs bin/ntf.bat, and a symlink there needs a privileged account")
    end

    local link = helper.test_data:path("bin/ntf")
    vim.fn.mkdir(vim.fs.dirname(link), "p")
    local ok, err = vim.uv.fs_symlink(vim.fs.joinpath(helper.root, "bin/ntf"), link)
    if not ok then
      error(err)
    end

    local path = spec("pass_spec.lua", PASSING)
    local env = { XDG_CACHE_HOME = helper.test_data:path("xdg_cache") }
    local obj = vim.system({ link, path }, { text = true, env = env }):wait(60000)

    assert.equal(0, obj.code)
    assert.match("2 passed", obj.stdout)
  end)

  it("runs the nvim $NTF_NVIM names", function()
    local path = spec("pass_spec.lua", PASSING)
    local env = { XDG_CACHE_HOME = helper.test_data:path("xdg_cache"), NTF_NVIM = vim.v.progpath }
    local obj = vim.system(cli({ path }), { text = true, cwd = helper.root, env = env }):wait(60000)

    assert.equal(0, obj.code)
    assert.match("2 passed", obj.stdout)
  end)

  it("fails instead of falling back to nvim when $NTF_NVIM names no runnable binary", function()
    local path = spec("pass_spec.lua", PASSING)
    local env = { XDG_CACHE_HOME = helper.test_data:path("xdg_cache"), NTF_NVIM = "ntf-no-such-nvim" }
    local obj = vim.system(cli({ path }), { text = true, cwd = helper.root, env = env }):wait(60000)

    assert.no.equal(0, obj.code)
    assert.no.match("2 passed", obj.stdout)
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

  it("reports a finally() an after_each registered, which runs past the callbacks", function()
    local path = spec(
      "late_finally_spec.lua",
      [[
local ntf = require("ntf")
ntf.after_each(function()
  ntf.finally(function() end)
end)
ntf.it("passes", function() end)
]]
    )
    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match("ERROR", obj.stdout)
    assert.match("finally%(%) outside a running test", obj.stdout)
  end)

  it("reports a finally() declared outside any test as a LOAD ERROR", function()
    local path = spec(
      "declared_finally_spec.lua",
      [[
local ntf = require("ntf")
ntf.finally(function() end)
ntf.it("never gets there", function() end)
]]
    )
    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match("LOAD ERROR", obj.stdout)
    assert.match("finally%(%) outside a running test", obj.stdout)
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
    local slow_but_finite = spec("slow_spec.lua", SLOW)
    local obj = run({ slow_but_finite }, { "--timeout=0" })

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

  it("fails a run whose workers declare a different tree than it was planned from", function()
    local path = spec(
      "diverging_spec.lua",
      [[
local ntf = require("ntf")
ntf.describe("g", function()
  if vim.env.NTF_SPEC_GROWS then
    ntf.it("grown", function() end)
  end
  ntf.it("planned", function() end)
end)
]]
    )
    local hook = spec("test_hook.lua", [[return { setup = function() vim.env.NTF_SPEC_GROWS = "1" end }]])

    local obj = run({ path }, { "--test-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("built a different tree than the run planned from", obj.stdout)
    assert.match('the run picked "g planned"', obj.stdout)
    assert.match('this position holds "g grown"', obj.stdout)
  end)

  it("matches --filter against the name a listing shows, a name spelled over several lines included", function()
    local path = spec(
      "folded_spec.lua",
      [[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("select (\nhoge\n)", function() end)
  ntf.it("plain", function() end)
end)
]]
    )

    local listed = run({ path }, { "list" })
    local filtered = run({ path }, { "--filter=select %(\\nhoge" })

    assert.match("g select %(\\nhoge\\n%)\n", listed.stdout)
    assert.equal(0, filtered.code)
    assert.match("1 tests: 1 passed", filtered.stdout)
  end)

  it("fails a file whose tests share a full name, naming both declaration sites", function()
    local path = spec(
      "shared_name_spec.lua",
      [[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("same name", function() end)
  ntf.it("same name", function() end)
end)
]]
    )

    local obj = run({ path })

    assert.equal(1, obj.code)
    assert.match('2 tests share the full name "g same name"', obj.stdout)
    assert.match("shared_name_spec%.lua:3, .*shared_name_spec%.lua:4", obj.stdout)
    assert.match("0 tests", obj.stdout)
  end)

  it(
    "puts a dependency on the runtimepath of the launcher and of every worker, so a spec reaches it at file scope",
    function()
      spec("deps/dependency/lua/dependency.lua", "return { value = 42 }")
      local hook = spec(
        "process_hook.lua",
        ([[
return {
  setup = function()
    vim.opt.runtimepath:append(%q)
  end,
}
]]):format(helper.test_data:path("deps/dependency"))
      )
      local path = spec(
        "dependency_spec.lua",
        [[
local ntf = require("ntf")
local dependency = require("dependency")
ntf.it("reaches the dependency", function()
  ntf.assert.equal(42, dependency.value)
end)
]]
      )

      local without_hook = run({ path })
      local with_hook = run({ path }, { "--process-hook=" .. hook })

      assert.equal(1, without_hook.code)
      assert.match("module 'dependency' not found", without_hook.stdout)
      assert.equal(0, with_hook.code)
      assert.match("1 passed", with_hook.stdout)
    end
  )

  it("exits 2 when the --process-hook module does not exist", function()
    local path = spec("pass_spec.lua", PASSING)

    local obj = run({ path }, { "--process-hook=/no/such/hook.lua" })

    assert.equal(2, obj.code)
    assert.match("%-%-process%-hook module not found", obj.stderr)
  end)

  it("exits 2 for a --process-hook module providing a teardown, which it has nowhere to run", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("process_hook.lua", [[return { setup = function() end, teardown = function() end }]])

    local obj = run({ path }, { "--process-hook=" .. hook })

    assert.equal(2, obj.code)
    assert.match("takes no teardown", obj.stderr)
  end)

  it("surfaces an error from the --process-hook module's setup before any test runs", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("process_hook.lua", [[return { setup = function() error("process boom") end }]])

    local obj = run({ path }, { "--process-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("%-%-process%-hook setup error", obj.stderr)
    assert.match("process boom", obj.stderr)
  end)

  it("runs the --global-hook module's setup and teardown once around the whole run", function()
    local log = vim.fs.joinpath(helper.test_data.full_path, "global_hook.log")
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
    local controller_plan = { "load" }
    local worker_of_one_top_level_test = { "load", "test" }
    assert.same(
      vim
        .iter({
          { "setup" },
          controller_plan,
          worker_of_one_top_level_test,
          worker_of_one_top_level_test,
          { "teardown" },
        })
        :flatten()
        :totable(),
      vim.fn.readfile(log)
    )
  end)

  it("surfaces a --global-hook teardown error without discarding the results", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("global_hook.lua", [[return { teardown = function() error("teardown boom") end }]])

    local obj = run({ path }, { "--global-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("teardown boom", obj.stderr)
    assert.match("2 passed", obj.stdout)
  end)

  it("tears the --global-hook down after a run that raised, and reports what raised", function()
    local path = spec("pass_spec.lua", PASSING)
    local log = vim.fs.joinpath(helper.test_data.full_path, "torn_down.log")
    local hook = spec(
      "global_hook.lua",
      ([[return { teardown = function() vim.fn.writefile({ "torn down" }, %q) end }]]):format(log)
    )

    -- WHY: a windows run resolves a leading-slash path onto the writable workspace drive, so the
    -- only directory no platform can create is one an existing file already occupies
    -- NOT: --coverage=/no/such/root/luacov.stats.out, which a windows run creates and writes
    local file_where_the_directory_has_to_be = spec("not_a_directory", "")
    local unwritable_stats_path = vim.fs.joinpath(file_where_the_directory_has_to_be, "luacov.stats.out")

    local obj = run({ path }, { "--global-hook=" .. hook, "--coverage=" .. unwritable_stats_path })

    assert.equal(1, obj.code)
    assert.match("ntf error:", obj.stderr)
    assert.same({ "torn down" }, vim.fn.readfile(log))
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
    local stats_file = vim.fs.joinpath(helper.test_data.full_path, "cov.stats.out")
    local obj = run({ path }, { "--coverage=" .. stats_file })

    assert.equal(0, obj.code)
    assert.match("2 passed", obj.stdout)
    assert.match("Coverage:", obj.stdout)
    assert.equal(1, vim.fn.filereadable(stats_file))
    local luacov_header = "^%d+:.+%.lua$"
    assert.match(luacov_header, vim.fn.readfile(stats_file)[1])
  end)

  it("fails a --coverage run whose --test-hook already holds the debug hook slot", function()
    local path = spec("pass_spec.lua", PASSING)
    local hook = spec("hook.lua", [[return { setup = function() debug.sethook(function() end, "l") end }]])
    local stats_file = vim.fs.joinpath(helper.test_data.full_path, "cov.stats.out")

    local obj = run({ path }, { "--coverage=" .. stats_file, "--test-hook=" .. hook })

    assert.equal(1, obj.code)
    assert.match("coverage was not measured", obj.stdout)
  end)

  it("fails a --coverage run whose test takes the debug hook slot over, instead of reporting partial counts", function()
    local path = spec(
      "hooky_spec.lua",
      [[
local ntf = require("ntf")
local it = ntf.it

it("takes the debug hook slot", function()
  debug.sethook(function() end, "l")
end)
]]
    )
    local stats_file = vim.fs.joinpath(helper.test_data.full_path, "cov.stats.out")

    local obj = run({ path }, { "--coverage=" .. stats_file })

    assert.equal(1, obj.code)
    assert.match("was replaced while the test ran", obj.stdout)
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
    local run_by_the_tests_but_not_the_code_under_test = "lua/vendor/dep.lua"
    helper.test_data:create_file(
      run_by_the_tests_but_not_the_code_under_test,
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

  it("measures code the specs sit beside, which no test tree of its own excludes", function()
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
      "lua/mod/init_spec.lua",
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

    local obj = helper.run_cli({ "--coverage=" .. stats_file, "lua" }, root)

    assert.equal(0, obj.code)
    assert.match("lua/mod/init%.lua%s+100%.0%%", obj.stdout)
    assert.no.match("init_spec%.lua", obj.stdout)
  end)

  it("leaves the test tree out even when the run names one spec file in it", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file("lua/mod.lua", "return { f = function() end }")
    local run_by_the_specs_but_not_the_code_under_test = "spec/dep.lua"
    helper.test_data:create_file(run_by_the_specs_but_not_the_code_under_test, "return { g = function() end }")
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'local mod = require("mod")',
        'local dep = dofile(vim.fs.joinpath(vim.fn.getcwd(), "spec/dep.lua"))',
        'describe("mod", function()',
        '  it("calls f", function()',
        "    dep.g()",
        "    assert.equal(nil, mod.f())",
        "  end)",
        "end)",
      }, "\n")
    )
    local stats_file = vim.fs.joinpath(root, "cov.stats.out")

    local obj = helper.run_cli({ "--coverage=" .. stats_file, "spec/mod_spec.lua" }, root)

    assert.equal(0, obj.code)
    assert.match("lua/mod%.lua", obj.stdout)
    assert.no.match("dep%.lua", obj.stdout)
    assert.no.match("dep%.lua", table.concat(vim.fn.readfile(stats_file), "\n"))
  end)

  it("fails a --coverage run that measured no line, instead of handing back a green n/a", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'describe("mod", function()',
        '  it("holds no code to its name", function()',
        "    assert.equal(1, 1)",
        "  end)",
        "end)",
      }, "\n")
    )

    local obj = helper.run_cli({ "--coverage=" .. vim.fs.joinpath(root, "cov.stats.out"), "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("Coverage: n/a", obj.stdout)
    assert.match("no measured line in: ", obj.stderr)
  end)

  it("keeps the test failure's exit code when the --coverage run also measured no line", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'describe("mod", function()',
        '  it("fails", function()',
        "    assert.equal(1, 2)",
        "  end)",
        "end)",
      }, "\n")
    )

    local obj = helper.run_cli({ "--coverage=" .. vim.fs.joinpath(root, "cov.stats.out"), "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("Coverage: n/a", obj.stdout)
    assert.no.match("no measured line in: ", obj.stderr)
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
    helper.test_data:create_file("lua/mod.lua", "return { f = function() end }")
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'local mod = require("mod")',
        'describe("mod", function()',
        '  it("passes", function()',
        "    assert.equal(nil, mod.f())",
        "  end)",
        "end)",
      }, "\n")
    )

    local obj = helper.run_cli({ "--coverage", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("1 passed", obj.stdout)
    local stats_file = vim.fn.glob(helper.test_data:path("xdg_cache") .. "/**/ntf/coverage/*.out")
    assert.equal(1, vim.fn.filereadable(stats_file))
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
  "    assert.equal(1, mod.min(2, 1))",
  "  end)",
  "end)",
}, "\n")

local MUTATION_DOFILE_SPEC = (
  MUTATION_SPEC:gsub('require%("mod"%)', 'dofile(vim.fs.joinpath(vim.fn.getcwd(), "lua/mod.lua"))')
)

local HANGING_MUTANTS_MODULE = table.concat({
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

--- @param it_opts string? the options the leaf declares, as source
--- @return string # a spec whose single test the module's hanging mutants are reached by
local function hanging_mutants_spec(it_opts)
  return table.concat({
    'local ntf = require("ntf")',
    'ntf.it("counts up to n", function()',
    '  ntf.assert.equal(3, require("loop").count(3))',
    "end" .. (it_opts and (", " .. it_opts) or "") .. ")",
  }, "\n")
end

--- @return string root, string results_file
local function mutation_project()
  local root = helper.test_data.full_path
  helper.test_data:create_file("lua/mod.lua", MUTATION_MODULE)
  helper.test_data:create_file("spec/mod_spec.lua", MUTATION_SPEC)
  return root, vim.fs.joinpath(root, "ntf-mutation.json")
end

describe("ntf mutation", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports the mutants a passing suite fails to detect", function()
    local root, results_file = mutation_project()

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("2 tests: 2 passed", obj.stdout)
    assert.match("Mutation: %d+%.%d%%", obj.stdout)
    assert.match("SURVIVED lua/mod%.lua:6:8:swap%-relational < %-> <=", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.survived)
    assert.equal(0, results.counts.not_applied)
    assert.equal(7, results.counts.killed)
  end)

  it("writes the results to the cache file for the working directory without --results", function()
    local root = mutation_project()

    local obj = helper.run_cli({ "mutation", "spec" }, root)

    assert.equal(0, obj.code)
    local results_file = vim.fn.glob(helper.test_data:path("xdg_cache") .. "/**/ntf/mutation/*.json")
    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.survived)
  end)

  it("reports a mutant no test reaches as uncovered", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "spec" }, root)

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

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("NO COVERAGE", obj.stdout)
    assert.match("Mutation: 100%.0%%", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(2, results.counts.killed)
    assert.equal(0, results.counts.no_coverage)
  end)

  it("mutates only the files under --target", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "mutation", "--target=lua/mod.lua", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("dead%.lua", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.same({ vim.fs.joinpath(root, "lua/mod.lua") }, vim.tbl_keys(results.files))
  end)

  it("exits 2 when --target holds no file to mutate, instead of reporting no mutants", function()
    local root = mutation_project()
    helper.test_data:create_file("doc/ntf.txt", "no lua here")

    local obj = helper.run_cli({ "mutation", "--strict", "--target=doc", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("no mutant found in: doc", obj.stderr)
  end)

  it("says the --config left every mutant out, rather than that the code holds none", function()
    local root = mutation_project()
    helper.test_data:create_file("mutation.json", vim.json.encode({ version = 1, operators = { "force-loop" } }))

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("unadopted", obj.stdout)
    assert.match("%-%-config leaves out every mutant in: ", obj.stderr)
    assert.no.match("no mutant found", obj.stderr)
  end)

  it("says the --config left every mutant out when an exclude entry drops the whole --target", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude = { { path = "lua/mod.lua", operators = "all", rationale = "left out for the test" } },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--target=lua/mod.lua", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("%-%-config leaves out every mutant in: lua/mod%.lua", obj.stderr)
    assert.no.match("no mutant found", obj.stderr)
  end)

  it("mutates nothing under an --exclude-code path", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/vendor/dep.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "mutation", "--exclude-code=lua/vendor", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("vendor", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.same({ vim.fs.joinpath(root, "lua/mod.lua") }, vim.tbl_keys(results.files))
  end)

  it("tears the --global-hook down after the mutation trials, so it sweeps what they left behind", function()
    local root = helper.test_data.full_path
    local leftovers = vim.fs.joinpath(root, "leftovers")
    helper.test_data:create_file("lua/mod.lua", MUTATION_MODULE)
    helper.test_data:create_file(
      "spec/mod_spec.lua",
      table.concat({
        ('vim.fn.mkdir(%q, "p")'):format(leftovers),
        ("vim.fn.writefile({}, vim.fs.joinpath(%q, tostring(vim.uv.os_getpid())))"):format(leftovers),
        MUTATION_SPEC,
      }, "\n")
    )
    local hook = helper.test_data:create_file(
      "hook/global.lua",
      ('return { teardown = function() vim.fn.delete(%q, "rf") end }'):format(leftovers)
    )

    local obj = helper.run_cli({ "mutation", "--target=lua/mod.lua", "--global-hook=" .. hook, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("Mutation: %d+%.%d%%", obj.stdout)
    assert.equal(0, vim.fn.isdirectory(leftovers))
  end)

  it("exits non-zero and reports the categories when --strict finds a survivor", function()
    local root, results_file = mutation_project()

    local obj = helper.run_cli({ "mutation", "--strict", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation gate failed: 1 survived", obj.stderr)
  end)

  it("exits non-zero when --strict finds a mutant no spec ever loaded", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("spec/mod_spec.lua", MUTATION_DOFILE_SPEC)

    local obj = helper.run_cli({ "mutation", "--strict", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("Mutation: n/a %(no mutant scored%)", obj.stdout)
    assert.match("8 not applied", obj.stdout)
    assert.match("NOT APPLIED lua/mod%.lua:", obj.stdout)
    assert.match("mutation gate failed: 8 not applied", obj.stderr)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(8, results.counts.not_applied)
  end)

  it("exits zero when --strict gates only no_coverage, which the fixture leaves empty", function()
    local root, results_file = mutation_project()

    local obj = helper.run_cli({ "mutation", "--strict=no_coverage", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
  end)

  it("leaves a mutant listed in the --config baseline out of the score as equivalent", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("Mutation: 100%.0%%", obj.stdout)
    assert.match("1 equivalent", obj.stdout)
    assert.no.match("SURVIVED", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.equivalent)
    assert.equal(0, results.counts.survived)
  end)

  it("runs the baseline entries alone under baseline verify, writing no results file", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
          },
        },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "baseline",
      "verify",
      "--config=mutation.json",
      "spec",
    }, root)

    assert.equal(0, obj.code)
    assert.match("Baseline: 1/1 entries re%-run", obj.stdout)
    local mutant_outside_the_baseline = "NO COVERAGE lua/dead%.lua:"
    assert.no.match(mutant_outside_the_baseline, obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)

  it("scores the other mutants in the same pass as --verify-baseline", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 12,
            operator = "swap-relational",
            original = ">",
            replacement = ">=",
            line = "  return n > 0",
            rationale = "stale: the boundary case is asserted",
          },
        },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "--config=mutation.json",
      "--verify-baseline",
      "--results=" .. results_file,
      "spec",
    }, root)

    assert.equal(1, obj.code)
    assert.match("Mutation: %d+%.%d%%", obj.stdout)
    assert.match("SURVIVED lua/mod%.lua:6:8:swap%-relational < %-> <=", obj.stdout)
    assert.match("BASELINE KILLABLE lua/mod%.lua:3:12:swap%-relational > %-> >=", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(1, results.counts.survived)

    local killable = vim.tbl_filter(function(record)
      return record.status == "baseline_killable"
    end, results.files[vim.fs.joinpath(root, "lua/mod.lua")])
    assert.equal(1, #killable)
  end)

  it("holds a baseline entry a trial killed only once, re-running that trial", function()
    local root = helper.test_data.full_path
    helper.test_data:create_file("lua/mod.lua", MUTATION_MODULE)
    helper.test_data:create_file(
      "spec/flaky_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        "local describe, it, assert = ntf.describe, ntf.it, ntf.assert",
        'local mod = require("mod")',
        'describe("mod", function()',
        '  it("fails the run after the one the whole gate waits on", function()',
        '    local counter = "runs"',
        "    local ran = vim.fn.filereadable(counter) == 1 and tonumber(vim.fn.readfile(counter)[1]) or 0",
        "    local runs = ran + 1",
        "    vim.fn.writefile({ tostring(runs) }, counter)",
        "    assert.is_true(mod.is_positive(1))",
        "    local the_baseline_run_and_then_the_first_trial = 2",
        "    assert.no.equal(the_baseline_run_and_then_the_first_trial, runs)",
        "  end)",
        "end)",
      }, "\n")
    )
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 12,
            operator = "swap-relational",
            original = ">",
            replacement = ">=",
            line = "  return n > 0",
            rationale = "no test here tells the boundary apart",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "baseline", "verify", "--config=mutation.json", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("Baseline: 1/1 entries re%-run", obj.stdout)
    assert.no.match("BASELINE KILLABLE", obj.stdout)
  end)

  it("exits 2 when baseline verify re-runs none of the entries it stands behind", function()
    local root = mutation_project()
    helper.test_data:create_file("doc/ntf.txt", "no lua here")
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
          },
        },
      })
    )

    local obj =
      helper.run_cli({ "mutation", "baseline", "verify", "--config=mutation.json", "--target=doc", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("baseline verify re%-ran none of the 1 entry in mutation%.json", obj.stderr)
  end)

  it("passes baseline verify on a config that lists no entry, which claims nothing to re-run", function()
    local root = mutation_project()
    helper.test_data:create_file("mutation.json", '{\n  "version": 1,\n  "operators": "all"\n}\n')

    local obj = helper.run_cli({ "mutation", "baseline", "verify", "--config=mutation.json", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("Baseline: 0/0 entries re%-run", obj.stdout)
  end)

  it("exits non-zero when baseline verify finds a baseline entry a test kills", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 12,
            operator = "swap-relational",
            original = ">",
            replacement = ">=",
            line = "  return n > 0",
            rationale = "stale: the boundary case is asserted",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "baseline", "verify", "--config=mutation.json", "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("BASELINE KILLABLE lua/mod%.lua:3:12:swap%-relational > %-> >=", obj.stdout)
    assert.match("mutation gate failed: 1 baseline entry killable", obj.stderr)
  end)

  it("writes the entry for a mutant into the baseline, which verify then re-runs", function()
    local root = mutation_project()
    helper.test_data:create_file("mutation.json", '{\n  "version": 1,\n  "operators": "all"\n}\n')

    local added = helper.run_cli({
      "mutation",
      "baseline",
      "add",
      "--config=mutation.json",
      "--mutant=lua/mod.lua:6:8:swap-relational",
      "--rationale=min(1, 2) is 1 on either side of the boundary",
    }, root)

    assert.equal(0, added.code)
    assert.match("added to mutation%.json: lua/mod%.lua:6:8:swap%-relational < %-> <=", added.stdout)

    local obj = helper.run_cli({ "mutation", "baseline", "verify", "--config=mutation.json", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("Baseline: 1/1 entries re%-run", obj.stdout)
  end)

  it("exits non-zero when the baseline it would add the entry to already carries it", function()
    local root = mutation_project()
    helper.test_data:create_file("mutation.json", '{\n  "version": 1,\n  "operators": "all"\n}\n')
    local argv = {
      "mutation",
      "baseline",
      "add",
      "--config=mutation.json",
      "--mutant=lua/mod.lua:6:8:swap-relational",
      "--rationale=min(1, 2) is 1 on either side of the boundary",
    }
    helper.run_cli(argv, root)

    local obj = helper.run_cli(argv, root)

    assert.equal(2, obj.code)
    assert.match("already in the baseline: lua/mod%.lua swap%-relational < %-> <=", obj.stderr)
  end)

  it("exits non-zero when a --config baseline entry matches nothing", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a <= b then",
            rationale = "stale: the marked line has changed",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("LOST BASELINE lua/mod%.lua swap%-relational: < %-> <=", obj.stdout)
    assert.match("mutation gate failed: 1 baseline entry matched no mutant", obj.stderr)
  end)

  it("exits non-zero when one baseline entry's content names two mutants", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "lua/twin.lua",
      table.concat({
        "local M = {}",
        "function M.first(n)",
        "  return n > 0",
        "end",
        "function M.second(n)",
        "  return n > 0",
        "end",
        "return M",
      }, "\n")
    )
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/twin.lua",
            col = 12,
            operator = "swap-relational",
            original = ">",
            replacement = ">=",
            line = "  return n > 0",
            rationale = "written for one of them, and there is no telling which",
          },
        },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "--target=lua/twin.lua",
      "--config=mutation.json",
      "--results=" .. results_file,
      "spec",
    }, root)

    assert.equal(1, obj.code)
    assert.match("AMBIGUOUS BASELINE lua/twin%.lua swap%-relational: > %-> >= names rows 3, 6", obj.stdout)
    assert.match("mutation gate failed: 1 ambiguous baseline position", obj.stderr)
  end)

  it("takes one entry per row once the position's entries name theirs", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "lua/twin.lua",
      table.concat({
        "local M = {}",
        "function M.first(n)",
        "  return n > 0",
        "end",
        "function M.second(n)",
        "  return n > 0",
        "end",
        "return M",
      }, "\n")
    )
    local function twin_entry(row, rationale)
      return {
        path = "lua/twin.lua",
        row = row,
        col = 12,
        operator = "swap-relational",
        original = ">",
        replacement = ">=",
        line = "  return n > 0",
        rationale = rationale,
      }
    end
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = { twin_entry(3, "the one first answers with"), twin_entry(6, "the one second answers with") },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "--target=lua/twin.lua",
      "--config=mutation.json",
      "--results=" .. results_file,
      "spec",
    }, root)

    assert.no.match("AMBIGUOUS BASELINE", obj.stdout)
    assert.no.match("LOST BASELINE", obj.stdout)
    assert.match("2 equivalent", obj.stdout)
  end)

  it("writes the row into an entry whose position holds a second mutant of the same content", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "lua/twin.lua",
      table.concat({
        "local M = {}",
        "function M.first(n)",
        "  return n > 0",
        "end",
        "function M.second(n)",
        "  return n > 0",
        "end",
        "return M",
      }, "\n")
    )
    local config = helper.test_data:create_file("mutation.json", vim.json.encode({ version = 1, operators = "all" }))

    local obj = helper.run_cli({
      "mutation",
      "baseline",
      "add",
      "--config=mutation.json",
      "--mutant=lua/twin.lua:6:12:swap-relational",
      "--rationale=second is only ever asked away from the boundary",
    }, root)

    assert.equal(0, obj.code)
    local written = vim.json.decode(table.concat(vim.fn.readfile(config), "\n"))
    assert.equal(1, #written.baseline)
    assert.equal(6, written.baseline[1].row)
  end)

  it("leaves a baseline entry outside --target unjudged, rather than losing every one of them", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/elsewhere.lua", MUTATION_MODULE)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/elsewhere.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a <= b then",
            rationale = "stale, but this run never enumerated the file it names",
          },
        },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "--target=lua/mod.lua",
      "--config=mutation.json",
      "--results=" .. results_file,
      "spec",
    }, root)

    assert.equal(0, obj.code)
    assert.no.match("LOST BASELINE", obj.stdout)
  end)

  it("exits non-zero when a --config baseline invariant_spec names no passing test", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
            invariant_spec = "mod names a test that was renamed away",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("UNPINNED BASELINE lua/mod%.lua swap%-relational: < %-> <=", obj.stdout)
    assert.match("mutation gate failed: 1 unpinned baseline entry", obj.stderr)
  end)

  it("keeps a --config baseline entry whose invariant_spec passed", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
            invariant_spec = "mod takes the min",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("UNPINNED BASELINE", obj.stdout)
  end)

  it("leaves a baseline invariant_spec unjudged where the run took part of the suite", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("spec/other_spec.lua", MUTATION_SPEC)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
            invariant_spec = "mod names a test this run never selected",
          },
        },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "--config=mutation.json",
      "--results=" .. results_file,
      "spec/mod_spec.lua",
    }, root)

    assert.equal(0, obj.code)
    assert.no.match("UNPINNED BASELINE", obj.stdout)
  end)

  it("leaves a --config exclude path unmutated", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude = {
          { path = "lua/dead.lua", operators = "all", rationale = "no spec drives it, so its mutants measure nothing" },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("lua/dead%.lua", obj.stdout)
    assert.match("SURVIVED lua/mod%.lua", obj.stdout)
  end)

  it("leaves out only the operators a --config exclude entry names, counting them apart", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude = {
          {
            path = "lua/mod.lua",
            operators = { "swap-relational" },
            rationale = "debt: the specs pin no pair the shifted boundary separates",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("2 excluded", obj.stdout)
    assert.no.match("SURVIVED", obj.stdout)
    assert.match("Mutation: 100%.0%%", obj.stdout)
  end)

  it("leaves the mutants of an operator the --config did not adopt out of the score, counting them apart", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("mutation.json", vim.json.encode({ version = 1, operators = { "swap-relational" } }))

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("Mutation: 50%.0%% %(1/2 mutants detected%)", obj.stdout)
    assert.match("6 unadopted", obj.stdout)
    assert.match("SURVIVED lua/mod%.lua:6:8:swap%-relational < %-> <=", obj.stdout)
  end)

  it("rejects a --config operators name no run produces before running the tests", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({ version = 1, operators = { "perturb-number", "swap-relatinal" } })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(2, obj.code)
    assert.match('operators names an operator no run produces: "swap%-relatinal"', obj.stderr)
    assert.no.match("passed", obj.stdout)
  end)

  it("exits non-zero when a --config exclude entry covers no measurable file", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude = {
          { path = "lua/gone.lua", operators = "all", rationale = "stale: the file it names is no longer there" },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("UNUSED EXCLUDE lua/gone%.lua", obj.stdout)
    assert.match("1 exclude entry covering nothing", obj.stderr)
  end)

  it("runs a --config exclude_spec path, but never picks its tests as a trial", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/e2e_only.lua", MUTATION_MODULE)
    helper.test_data:create_file("spec/e2e_spec.lua", (MUTATION_SPEC:gsub('require%("mod"%)', 'require("e2e_only")')))
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude_spec = {
          {
            path = "spec/e2e_spec.lua",
            rationale = "end-to-end, so running it once per mutant costs more than it finds",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("4 tests: 4 passed", obj.stdout)
    assert.match("NO COVERAGE lua/e2e_only%.lua:", obj.stdout)
    assert.match("SURVIVED lua/mod%.lua:6", obj.stdout)
  end)

  it("stops the run when a --config exclude_spec path fails", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("spec/e2e_spec.lua", FAILING)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude_spec = { { path = "spec/e2e_spec.lua", rationale = "end-to-end, so it never drives a mutant" } },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation run skipped: the tests must pass first", obj.stderr)
  end)

  it("exits non-zero when a --config exclude_spec entry covers no spec file", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude_spec = { { path = "spec/gone_spec.lua", rationale = "stale: the spec it names is no longer there" } },
      })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("UNUSED EXCLUDE SPEC spec/gone_spec%.lua", obj.stdout)
    assert.match("1 exclude_spec entry covering nothing", obj.stderr)
  end)

  it("leaves a --config exclude_spec entry outside the run's spec paths unjudged", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("spec/other/e2e_spec.lua", MUTATION_SPEC)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude_spec = {
          { path = "spec/other/e2e_spec.lua", rationale = "end-to-end, so it never drives a mutant" },
        },
      })
    )

    local obj = helper.run_cli({
      "mutation",
      "--config=mutation.json",
      "--results=" .. results_file,
      "spec/mod_spec.lua",
    }, root)

    assert.equal(0, obj.code)
    assert.no.match("UNUSED EXCLUDE SPEC", obj.stdout)
  end)

  it("rejects an invalid --config exclude before running the tests", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({ version = 1, operators = "all", exclude = { { path = "x" } } })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("exclude%[1%] needs a string rationale", obj.stderr)
  end)

  it("rejects an invalid --config baseline before running the tests", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({ version = 1, operators = "all", baseline = { { path = "x" } } })
    )

    local obj = helper.run_cli({ "mutation", "--config=mutation.json", "--results=" .. results_file, "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("baseline%[1%]", obj.stderr)
    assert.no.match("passed", obj.stdout)
  end)

  it("counts the mutants that hang the tests as detected", function()
    local root = helper.test_data.full_path
    local results_file = vim.fs.joinpath(root, "ntf-mutation.json")
    helper.test_data:create_file("lua/loop.lua", HANGING_MUTANTS_MODULE)
    helper.test_data:create_file("spec/loop_spec.lua", hanging_mutants_spec())

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "--timeout=1000", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("2 timeout", obj.stdout)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(2, results.counts.timeout)
  end)

  it("bounds the trials of a test the run leaves untimed, whose hanging mutants would outlast the run", function()
    local root = helper.test_data.full_path
    local results_file = vim.fs.joinpath(root, "ntf-mutation.json")
    helper.test_data:create_file("lua/loop.lua", HANGING_MUTANTS_MODULE)
    helper.test_data:create_file("spec/loop_spec.lua", hanging_mutants_spec("{ timeout = 0 }"))

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "spec" }, root)

    assert.equal(0, obj.code)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(2, results.counts.timeout)
  end)

  it("gives a slow test's trials the time its own timeout allows, past what the run's would", function()
    local root = helper.test_data.full_path
    local results_file = vim.fs.joinpath(root, "ntf-mutation.json")
    helper.test_data:create_file(
      "lua/slow.lua",
      table.concat({
        "local M = {}",
        "function M.answer()",
        "  return true",
        "end",
        "return M",
      }, "\n")
    )
    helper.test_data:create_file(
      "spec/slow_spec.lua",
      table.concat({
        'local ntf = require("ntf")',
        'ntf.it("answers once it has slept longer than the run waits", function()',
        "  vim.uv.sleep(1200)",
        '  ntf.assert.is_true(require("slow").answer())',
        "end, { timeout = 30000 })",
      }, "\n")
    )

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "--timeout=1000", "spec" }, root)

    assert.equal(0, obj.code)

    local results = vim.json.decode(table.concat(vim.fn.readfile(results_file), "\n"))
    assert.equal(0, results.counts.timeout)
    assert.equal(1, results.counts.killed)
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

    local obj = helper.run_cli({ "mutation", "--results=" .. results_file, "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation run skipped", obj.stderr)
    assert.no.match("Mutation:", obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)
end)

describe("ntf list", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("lists every test as path:line: full name", function()
    local path = spec("pass_spec.lua", PASSING)
    local obj = run({ path }, { "list" })

    assert.equal(0, obj.code)
    assert.match("pass_spec%.lua:%d+ group adds\n", obj.stdout)
    assert.match("pass_spec%.lua:%d+ group also passes\n", obj.stdout)
    assert.no.match("passed", obj.stdout)
  end)

  it("exits 0 for a failing spec because the test bodies never run", function()
    local path = spec("fail_spec.lua", FAILING)
    local obj = run({ path }, { "list" })

    assert.equal(0, obj.code)
    assert.match("fail_spec%.lua:%d+ group explodes\n", obj.stdout)
    assert.no.match("FAIL", obj.stdout)
  end)

  it("lists only the tests matching --filter", function()
    local path = spec("filter_spec.lua", FILTERABLE)
    local obj = run({ path }, { "list", "--filter=keep me" })

    assert.equal(0, obj.code)
    assert.match("keep me", obj.stdout)
    assert.no.match("drop me", obj.stdout)
  end)

  it("reports a LOAD ERROR on stderr and exits 1, still listing the loadable tests", function()
    spec("broken_spec.lua", LOAD_ERROR)
    spec("pass_spec.lua", PASSING)
    local obj = run({ helper.test_data.full_path }, { "list" })

    assert.equal(1, obj.code)
    assert.match("pass_spec%.lua:%d+ group adds\n", obj.stdout)
    assert.match("LOAD ERROR", obj.stderr)
    assert.match("top%-level boom", obj.stderr)
    assert.no.match("LOAD ERROR", obj.stdout)
  end)

  it("runs the tests and lists the mutants alone, leaving the test list to `ntf list`", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("lua/dead.lua", MUTATION_MODULE)

    local obj = helper.run_cli({ "mutation", "list", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("lua/mod%.lua:6:%d+:swap%-relational < %-> <= %(covered by 1 test%)\n", obj.stdout)
    assert.match("lua/dead%.lua:%d+:%d+:[%w-]+ .* %(no coverage%)\n", obj.stdout)
    assert.no.match("mod detects positives at the boundary", obj.stdout)
    assert.no.match("Mutation:", obj.stdout)
    assert.no.match("passed", obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)

  it("writes what a test printed to stderr, keeping stdout to the mutant list", function()
    local root = mutation_project()
    helper.test_data:create_file("spec/noisy_spec.lua", NOISY)

    local obj = helper.run_cli({ "mutation", "list", "spec" }, root)

    assert.equal(0, obj.code)
    assert.match("from print", obj.stderr)
    assert.no.match("from print", obj.stdout)
  end)

  it("exits 2 when the mutant list would hold nothing under --target", function()
    local root = mutation_project()
    helper.test_data:create_file("doc/ntf.txt", "no lua here")

    local obj = helper.run_cli({ "mutation", "list", "--target=doc", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("no mutant found in: doc", obj.stderr)
    assert.no.match("mod detects positives", obj.stdout)
  end)

  it("says the --config left every listed mutant out, rather than that the code holds none", function()
    local root = mutation_project()
    helper.test_data:create_file("mutation.json", vim.json.encode({ version = 1, operators = { "force-loop" } }))

    local obj = helper.run_cli({ "mutation", "list", "--config=mutation.json", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("%-%-config leaves out every mutant in: ", obj.stderr)
    assert.no.match("no mutant found", obj.stderr)
  end)

  it("says the --config left every listed mutant out when an exclude entry drops the whole --target", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude = { { path = "lua/mod.lua", operators = "all", rationale = "left out for the test" } },
      })
    )

    local obj = helper.run_cli({ "mutation", "list", "--config=mutation.json", "--target=lua/mod.lua", "spec" }, root)

    assert.equal(2, obj.code)
    assert.match("%-%-config leaves out every mutant in: lua/mod%.lua", obj.stderr)
    assert.no.match("no mutant found", obj.stderr)
  end)

  it("skips the mutant list when the tests fail, reporting the failure on stderr", function()
    local root, results_file = mutation_project()
    helper.test_data:create_file("spec/fail_spec.lua", FAILING)

    local obj = helper.run_cli({ "mutation", "list", "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("mutation list skipped", obj.stderr)
    assert.match("FAIL", obj.stderr)
    assert.equal("", obj.stdout)
    assert.equal(0, vim.fn.filereadable(results_file))
  end)

  it("exits non-zero when a --config baseline entry matches no listed mutant", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a <= b then",
            rationale = "stale: the marked line has changed",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "list", "--config=mutation.json", "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("lua/mod%.lua:6:%d+:swap%-relational < %-> <= %(covered by 1 test%)\n", obj.stdout)
    assert.match("LOST BASELINE lua/mod%.lua swap%-relational: < %-> <=", obj.stdout)
    assert.match("mutation gate failed: 1 baseline entry matched no mutant", obj.stderr)
  end)

  it("exits non-zero when a --config baseline invariant_spec names no passing test of the listed run", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/mod.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a < b then",
            rationale = "min(1, 2) is 1 on either side of the boundary",
            invariant_spec = "mod names a test that was renamed away",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "list", "--config=mutation.json", "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("UNPINNED BASELINE lua/mod%.lua swap%-relational: < %-> <=", obj.stdout)
    assert.match("mutation gate failed: 1 unpinned baseline entry", obj.stderr)
  end)

  it("exits non-zero when a --config exclude or exclude_spec entry covers nothing listed", function()
    local root = mutation_project()
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        exclude = {
          { path = "lua/gone.lua", operators = "all", rationale = "stale: the file it names is no longer there" },
        },
        exclude_spec = { { path = "spec/gone_spec.lua", rationale = "stale: the spec it names is no longer there" } },
      })
    )

    local obj = helper.run_cli({ "mutation", "list", "--config=mutation.json", "spec" }, root)

    assert.equal(1, obj.code)
    assert.match("UNUSED EXCLUDE lua/gone%.lua", obj.stdout)
    assert.match("UNUSED EXCLUDE SPEC spec/gone_spec%.lua", obj.stdout)
    assert.match("1 exclude entry covering nothing", obj.stderr)
    assert.match("1 exclude_spec entry covering nothing", obj.stderr)
  end)

  it("leaves a --config baseline entry for a file outside the --target unjudged", function()
    local root = mutation_project()
    helper.test_data:create_file("lua/elsewhere.lua", MUTATION_MODULE)
    helper.test_data:create_file(
      "mutation.json",
      vim.json.encode({
        version = 1,
        operators = "all",
        baseline = {
          {
            path = "lua/elsewhere.lua",
            col = 8,
            operator = "swap-relational",
            original = "<",
            replacement = "<=",
            line = "  if a <= b then",
            rationale = "stale, but this listing never enumerated the file it names",
          },
        },
      })
    )

    local obj = helper.run_cli({ "mutation", "list", "--config=mutation.json", "--target=lua/mod.lua", "spec" }, root)

    assert.equal(0, obj.code)
    assert.no.match("LOST BASELINE", obj.stdout)
  end)
end)
