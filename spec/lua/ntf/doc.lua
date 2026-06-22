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
ntf can run describe/it units in separate Neovim processes.

- `--isolate=file`: one process per spec file
- `--isolate=describe`: one process per top-level describe
- `--isolate=it` (default): one process per it

describe/it take an optional opts table; opt a single block into its own process
with `opts.isolate`:
>lua
  describe("a whole block in its own process", function() end, { isolate = true })

  it("a single test in a fresh process", function() end, { isolate = true })
<]]
      end,
    },
    {
      name = "TIMEOUT",
      body = function()
        return [[
Each worker process is killed if it runs longer than a timeout, so a hung test
fails fast instead of stalling the whole run. The global default is set with
`--timeout=MS` (default 60000; `--timeout=0` disables it).

describe/it can override it per node with `opts.timeout` (milliseconds):
>lua
  it("must be quick", function() end, { timeout = 1000 })

  describe("slow integration block", function() end, { timeout = 30000 })
<
The timeout is enforced at the granularity of the isolation unit (the process),
not the individual test, because a timed-out process is killed as a whole. A
per-node `opts.timeout` therefore only takes effect when that node is its own
isolation unit:

- with `--isolate=it` (default) every `it` is its own process, so every
  `it`-level `opts.timeout` is enforced precisely
- a node marked `opts.isolate = true` becomes its own process, so its
  `opts.timeout` is enforced too
- otherwise (e.g. several `it`s sharing one process under `--isolate=file`), only
  the unit node's timeout applies; inner per-`it` timeouts are ignored, and the
  process timeout bounds the unit as a whole

A timed-out worker is reported as an error ("worker timed out after Nms").]]
      end,
    },
    {
      name = "OUTPUT",
      body = function()
        return [[
`print` and `io.write` output emitted while a test runs is captured and shown in
the report, attributed to the test case it came from (under the failure block for
a failing test, or its own `OUTPUT <name>` block otherwise).

Opt a single test out of having its output shown with `opts.output = "never"`:
>lua
  it("noisy but uninteresting", function()
    print("ignored")
  end, { output = "never" })
<
Other output channels (`io.stdout:write`, `vim.api.nvim_echo`, native writes) are
not captured.]]
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
It runs busted-style `*_spec.lua` files and can execute `describe`/`it` units in
separate Neovim processes.

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
