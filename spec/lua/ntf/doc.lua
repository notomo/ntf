vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.core.controller.args")
local plugin_name = vim.env.PLUGIN_NAME

-- flags / usage come from core.controller.args so they are never duplicated here
local usage = args.usage()

-- The "writing specs" snippet lives in one runnable file, reused by both the
-- vimdoc chapter and the README. A spec is not directly `dofile`-able (it needs
-- ntf's build context), so verify it by running it through the real CLI; a
-- broken example fails `make doc` instead of shipping.
local example_path = ("./spec/lua/%s/example.lua"):format(plugin_name)
local example_result = vim.system({ "./bin/ntf", example_path }):wait()
if example_result.code ~= 0 then
  error(("example failed to run: %s\n%s"):format(example_path, example_result.stdout .. example_result.stderr))
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
        return [[
`--hook=PATH` loads the given Lua module in every worker (via `dofile`). The
module returns a table with optional `setup` and `teardown` functions that run
once per worker, outside everything the spec itself defines: `setup` before the
spec is built, `teardown` after the worker's test has run. They are deliberately
not named `before_each`/`after_each` — those are per-test spec hooks; `setup`/
`teardown` bracket the whole worker instead.
>lua
  -- hook.lua
  return {
    setup = function() end,
    teardown = function() end,
  }
<
>sh
  ntf --hook=./hook.lua
<
A relative path resolves against the working directory (the plugin under test).
An error raised while loading the module or from `setup` is reported as a load
error. A `teardown` error is reported too — as an error entry alongside the
worker's results, so it fails the run without discarding the results already
produced.

Because `setup` runs before the spec is built, it is the injection point for a
debugger: the code under test loads while the debugger is already attached. ntf
has no debugger dependency of its own:
>lua
  -- debug.lua
  return {
    setup = function()
      require("lldebugger").start()
    end,
  }
<
>sh
  ntf --hook=./debug.lua --jobs=1 --filter='the test name'
<
Tests run in parallel worker processes whose stdout ntf captures, so to actually
attach a debugger keep it to a single worker (`--jobs=1`, and narrow to one test
with `--filter`). Wiring the debugger transport itself is up to your module.]]
      end,
    },
    {
      name = "COVERAGE",
      body = function()
        return [[
`--coverage` measures line coverage of the code under test while the specs run.
It measures every file under the working directory except the test tree: any
`*_spec.lua` file and the test directory the specs were found in (its top-level
directory under the working directory — `spec/` by default, but whatever path you
pass) are excluded, so anything sitting alongside the specs there (such as cloned
test dependencies) is left out too. It needs no extra install: ntf sets a Lua line
hook in each worker, merges the per-worker counts, prints a short summary, and
writes a `luacov.stats.out` (override the path with `--coverage=FILE`):
>sh
  ntf --coverage
<
The built-in summary is intentionally simple (its line classification is a
heuristic). For an authoritative or HTML report, point LuaCov — which ntf does
not depend on — at the same stats file:
>sh
  luarocks install luacov
  luacov          # reads luacov.stats.out -> luacov.report.out
<
Coverage forces the interpreter (`jit.off()`) in each worker so the line hook is
not skipped by the JIT, which makes a `--coverage` run slower than a plain one.]]
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

  local content = ([[
# %s

> [!WARNING]
> WIP

ntf (neovim test framework) is a dependency-free test runner for Neovim plugins.
It runs busted-style `*_spec.lua` files, executing each `it` in its own fresh
Neovim process so state never leaks between tests.

## Usage

```
%s
```

## Writing specs

```lua
%s```
]]):format(plugin_name, usage, example)

  util.write("README.md", content)
end
gen_readme()
