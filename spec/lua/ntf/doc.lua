vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.cli.args")
local plugin_name = vim.env.PLUGIN_NAME

-- flags / usage come from cli.args so they are never duplicated here
local usage = args.usage()

require("genvdoc").generate(plugin_name, {
  source = { patterns = { ("lua/%s/init.lua"):format(plugin_name) } },
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

- `--isolate=file` (default): one process per spec file
- `--isolate=describe`: one process per top-level describe
- `--isolate=it`: one process per it

describe/it take an optional opts table; opt a single block into its own process
with `opts.isolate`:
>lua
  describe("a whole block in its own process", function() end, { isolate = true })

  it("a single test in a fresh process", function() end, { isolate = true })
<]]
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
