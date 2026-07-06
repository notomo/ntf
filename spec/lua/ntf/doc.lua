vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.core.controller.args")
local plugin_name = vim.env.PLUGIN_NAME

local usage = args.usage()

-- Every code element in the docs below is backed by something executed here:
-- snippets are runnable files, and documented command lines are assembled from
-- the same values as a verified run. A snippet that stops working (or names a
-- removed flag) fails `make doc` instead of shipping.

local exercised_flags = {} --- @type table<string, true> keyed by the `args.flags` entry name

--- @param name string bare flag token, e.g. "--test-hook"
--- @return string # `name` unchanged, if `args.flags` documents it
local flag = function(name)
  for _, f in ipairs(args.flags) do
    for _, alt in ipairs(vim.split(f.name, ", ", { plain = true })) do
      if alt == name or vim.startswith(alt, name .. "=") or vim.startswith(alt, name .. "[") then
        exercised_flags[f.name] = true
        return name
      end
    end
  end
  error("not a documented flag: " .. name)
end

--- @param cli_args string[]
--- @param env table<string,string>? extra environment, merged into the inherited one
local run_ntf = function(cli_args, env)
  local cmd = vim.list_extend({ "./bin/ntf" }, cli_args)
  local result = vim.system(cmd, { env = env }):wait()
  if result.code ~= 0 then
    error(("failed to run: %s\n%s"):format(table.concat(cmd, " "), result.stdout .. result.stderr))
  end
end

-- The "writing specs" snippet is reused by both the vimdoc chapter and the
-- README. A spec is not directly `dofile`-able (it needs ntf's build context),
-- so verify it by running it through the real CLI.
local example_path = ("./spec/lua/%s/example.lua"):format(plugin_name)
run_ntf({ example_path })

local doc_dir = ("./spec/lua/%s/doc"):format(plugin_name)

-- Documented hook commands show a user-local path; the flag token and the file
-- basename are shared with the verified run so they cannot diverge.
local test_hook_path = doc_dir .. "/test_hook.lua"
run_ntf({ ("%s=%s"):format(flag("--test-hook"), test_hook_path), example_path })
local test_hook_command = ("ntf %s=./%s"):format(flag("--test-hook"), vim.fs.basename(test_hook_path))

local global_hook_path = doc_dir .. "/global_hook.lua"
run_ntf({ ("%s=%s"):format(flag("--global-hook"), global_hook_path), example_path })
local global_hook_command = ("ntf %s=./%s"):format(flag("--global-hook"), vim.fs.basename(global_hook_path))

-- The debugger snippet requires lldebugger, which ntf does not depend on;
-- satisfy the `require` with a stub module exposed via LUA_PATH, which the
-- workers inherit.
local debug_hook_path = doc_dir .. "/debug.lua"
local stub_dir = vim.fn.tempname()
vim.fn.mkdir(stub_dir, "p")
local stub = assert(io.open(stub_dir .. "/lldebugger.lua", "w"))
stub:write("return { start = function() end }\n")
stub:close()
run_ntf({
  ("%s=%s"):format(flag("--test-hook"), debug_hook_path),
  flag("--jobs") .. "=1",
  flag("--filter") .. "=does something",
  example_path,
}, { LUA_PATH = stub_dir .. "/?.lua;;" })
local debug_command = ("ntf %s=./%s %s=1 %s='the test name'"):format(
  flag("--test-hook"),
  vim.fs.basename(debug_hook_path),
  flag("--jobs"),
  flag("--filter")
)

-- The documented coverage command is bare; the verified run redirects the stats
-- file to a temp path to avoid littering the working tree.
local coverage_flag = flag("--coverage")
run_ntf({ ("%s=%s"):format(coverage_flag, vim.fn.tempname()), example_path })
local coverage_command = "ntf " .. coverage_flag

-- The flags above appear in documented commands; the rest of the usage block is
-- backed by these runs, so every documented flag fails `make doc` when it stops
-- working.
run_ntf({ flag("--timeout") .. "=60000", example_path })
run_ntf({ flag("--shuffle") .. "=42", example_path })
run_ntf({ flag("--help") })
for _, f in ipairs(args.flags) do
  if not exercised_flags[f.name] then
    error("documented flag has no verified run: " .. f.name)
  end
end

-- The README setup snippet runs in this very process (ntf is on the runtimepath
-- here just like in a user config) and must actually make `ntf` resolvable.
local setup_path = doc_dir .. "/setup.lua"
dofile(setup_path)
if vim.fn.exepath("ntf") == "" then
  error("setup snippet did not put ntf on PATH: " .. setup_path)
end

require("genvdoc").generate(plugin_name, {
  source = {
    patterns = {
      ("lua/%s/init.lua"):format(plugin_name),
      ("lua/%s/helper.lua"):format(plugin_name),
      ("lua/%s/assert/meta.lua"):format(plugin_name),
      ("lua/%s/assert/init.lua"):format(plugin_name),
    },
  },
  chapters = {
    {
      name = "USAGE",
      body = function()
        return util.help_code_block(usage)
      end,
    },
    {
      name = "WRITING SPECS",
      body = function()
        return util.help_code_block_from_file(example_path, { language = "lua" })
      end,
    },
    {
      name = "HOOKS",
      body = function()
        return table.concat({
          [[
`--test-hook=PATH` loads the given Lua module in every worker (via `dofile`).
Each test runs in its own worker process, so the module's optional `setup` and
`teardown` functions run once per test — but outside everything the spec itself
defines: `setup` before the spec is built, `teardown` after the worker's test
has run. They are deliberately not named `before_each`/`after_each` — those are
spec hooks around the test body; `setup`/`teardown` bracket the whole worker
instead.]],
          util.help_code_block_from_file(test_hook_path, { language = "lua" }),
          util.help_code_block(test_hook_command, { language = "sh" }),
          [[
A relative path resolves against the working directory (the plugin under test).
An error raised while loading the module or from `setup` is reported as a load
error. A `teardown` error is reported too — as an error entry alongside the
worker's results, so it fails the run without discarding the results already
produced.

`--global-hook=PATH` takes a module with the same contract but runs it once in
the launcher process instead of in every worker: `setup` before any spec file is
loaded, `teardown` after all workers have finished. Use it for state shared by
the whole run — start a server once, build a fixture once — while `--test-hook`
remains the per-test bracket:]],
          util.help_code_block(global_hook_command, { language = "sh" }),
          [[
An error raised while loading the module or from its `setup` aborts the run
before any test starts. A `teardown` error is reported after the results, so it
fails the run without discarding them.

Because `setup` runs before the spec is built, it is the injection point for a
debugger: the code under test loads while the debugger is already attached. ntf
has no debugger dependency of its own:]],
          util.help_code_block_from_file(debug_hook_path, { language = "lua" }),
          util.help_code_block(debug_command, { language = "sh" }),
          [[
Tests run in parallel worker processes whose stdout ntf captures, so to actually
attach a debugger keep it to a single worker (`--jobs=1`, and narrow to one test
with `--filter`). Wiring the debugger transport itself is up to your module.]],
        }, "\n")
      end,
    },
    {
      name = "COVERAGE",
      body = function()
        return table.concat({
          [[
`--coverage` measures line coverage of the code under test while the specs run.
It measures every file under the working directory except the test tree: any
`*_spec.lua` file and the test directory the specs were found in (its top-level
directory under the working directory — `spec/` by default, but whatever path you
pass) are excluded, so anything sitting alongside the specs there (such as cloned
test dependencies) is left out too. A measured file no test executed still shows
up, at 0% (LuaCATS meta files are skipped: they never run by definition). It
needs no extra install: ntf sets a Lua line
hook in each worker, merges the per-worker counts, prints a short summary, and
writes a `luacov.stats.out` (override the path with `--coverage=FILE`):]],
          util.help_code_block(coverage_command, { language = "sh" }),
          [[
The built-in summary is intentionally simple (its line classification is a
heuristic). For an authoritative or HTML report, point LuaCov — which ntf does
not depend on — at the same stats file:
>sh
  luarocks install luacov
  luacov          # reads luacov.stats.out -> luacov.report.out
<
Coverage forces the interpreter (`jit.off()`) in each worker so the line hook is
not skipped by the JIT, which makes a `--coverage` run slower than a plain one.]],
        }, "\n")
      end,
    },
    {
      name = function(group)
        return "Lua module: " .. group
      end,
      group = function(node)
        if node.declaration == nil or node.declaration.type ~= "function" then
          return nil
        end
        -- assert/meta.lua is a @meta types file, but its functions are called as
        -- `ntf.assert.X`; document them under ntf.assert with `*ntf.assert.X()*` tags.
        if node.declaration.module == "ntf.assert.meta" then
          node.declaration.module = "ntf.assert"
        end
        return node.declaration.module
      end,
    },
    {
      name = "STRUCTURE",
      group = function(node)
        if node.declaration == nil or not vim.tbl_contains({ "class", "alias" }, node.declaration.type) then
          return nil
        end
        return "STRUCTURE"
      end,
    },
  },
})

local gen_readme = function()
  local example = util.read_all(example_path)
  local setup = util.read_all(setup_path)

  local content = ([[
# %s

> [!WARNING]
> WIP

ntf (neovim test framework) is a dependency-free test runner for Neovim plugins.
It runs busted-style `*_spec.lua` files, executing each `it` in its own fresh
Neovim process so state never leaks between tests.

## Setup

`bin/ntf` is the CLI. With ntf installed as a Neovim plugin, you can expose the
command to `:terminal` (and anything else Neovim spawns) by prepending its `bin`
directory to `$PATH`:

```lua
%s```

## Usage

```
%s
```

## Writing specs

```lua
%s```
]]):format(plugin_name, setup, usage, example)

  util.write("README.md", content)
end
gen_readme()
