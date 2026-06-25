vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.core.controller.args")
local plugin_name = vim.env.PLUGIN_NAME

-- flags / usage come from core.controller.args so they are never duplicated here
local usage = args.usage()

require("genvdoc").generate(plugin_name, {
  source = {
    patterns = {
      ("lua/%s/init.lua"):format(plugin_name),
      ("lua/%s/helper.lua"):format(plugin_name),
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
        return [[
The test API is pulled from `require("ntf")` explicitly (no global injection):
>lua
  local ntf = require("ntf")
  local describe, it = ntf.describe, ntf.it
  local before_each, after_each = ntf.before_each, ntf.after_each
  local assert = ntf.assert

  describe("group", function()
    it("does something", function()
      assert.equal(1, 1)
    end)
  end)
<]]
      end,
    },
    {
      name = "ISOLATION",
      body = function()
        return [[
Every `it` runs in its own fresh Neovim process. This is not configurable: state
never leaks between tests, because no two tests ever share a process.]]
      end,
    },
    {
      name = "TIMEOUT",
      body = function()
        return [[
Each worker process is killed if it runs longer than a timeout, so a hung test
fails fast instead of stalling the whole run. The global default is set with
`--timeout=MS` (default 60000; `--timeout=0` disables it).

An `it` can override the default with `opts.timeout` (milliseconds):
>lua
  it("must be quick", function() end, { timeout = 1000 })
<
Because every `it` is its own process, an `it`-level `opts.timeout` is always
enforced precisely.

A timed-out worker is reported as an error ("worker timed out after Nms").]]
      end,
    },
    {
      name = "OUTPUT",
      body = function()
        return [[
Everything a worker writes while it runs is captured and shown in the report as
an `OUTPUT` block, labeled with the test case's full name. Both standard streams
are included: `io.write`, `io.stdout:write` and native writes on stdout, plus
`print`, `vim.api.nvim_echo` and other messages, which Neovim routes to stderr;
stdout is shown before stderr.

Each `it` runs in its own worker, so a spec file with several `it`s that write
output produces several `OUTPUT` blocks.]]
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
      name = function(group)
        return "Lua module: " .. group
      end,
      group = function(node)
        if node.declaration == nil or node.declaration.type ~= "function" then
          return nil
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

The test API is pulled from `require("ntf")` explicitly (no global injection):

```lua
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it
local assert = ntf.assert

describe("group", function()
  it("does something", function()
    assert.equal(1, 1)
  end)
end)
```
]]):format(plugin_name, usage)

  util.write("README.md", content)
end
gen_readme()
