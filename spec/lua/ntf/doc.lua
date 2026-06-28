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
      name = "DEBUGGING",
      body = function()
        return [[
`--setup=PATH` runs the given Lua script in every worker (via `dofile`) before
building or running any spec. ntf has no debugger dependency of its own; this is
just an injection point, so you can drop in whatever you need:
>sh
  echo 'require("lldebugger").start()' > debug.lua
  ntf --setup=./debug.lua --jobs=1 --filter='the test name'
<
A relative path resolves against the working directory (the plugin under test),
and an error raised by the script is reported as a load error.

Tests run in parallel worker processes whose stdout ntf captures, so to actually
attach a debugger keep it to a single worker (`--jobs=1`, and narrow to one test
with `--filter`). Wiring the debugger transport itself is up to your script.]]
      end,
    },
    {
      name = "COVERAGE",
      body = function()
        return [[
`--coverage` measures line coverage of the code under test (every file under the
working directory that is not a `*_spec.lua`) while the specs run. It needs no
extra install: ntf sets a Lua line hook in each worker, merges the per-worker
counts, prints a short summary, and writes a `luacov.stats.out` (override the
path with `--coverage=FILE`):
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
