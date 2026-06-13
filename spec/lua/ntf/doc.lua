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
]]):format(plugin_name, usage)

  util.write("README.md", content)
end
gen_readme()
