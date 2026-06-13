# ntf

> [!WARNING]
> WIP

ntf (neovim test framework) is a dependency-free test runner for Neovim plugins.
It runs busted-style `*_spec.lua` files and can execute `describe`/`it` units in
separate Neovim processes.

## Usage

```
Usage: ntf [options] <spec-file-or-dir>...

Options:
  --isolate=LEVEL  process split granularity: file|describe|it (default: file)
  --jobs=N         max parallel nvim workers (default: cpu count)
  --shuffle        randomize test order
  --seed=N         seed used with --shuffle (default: time based)
  --json           emit machine-readable JSON instead of the text report
  --no-color       disable ANSI colors
  --slow=MS        report tests slower than MS milliseconds
  -h, --help       show this help
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
