# ntf

> [!WARNING]
> WIP

ntf (neovim test framework) is a dependency-free test runner for Neovim plugins.
It runs busted-style `*_spec.lua` files, executing each `it` in its own fresh
Neovim process so state never leaks between tests.

## Usage

```
Usage: ntf [options] [spec-file-or-dir...]

Options:
  --timeout=MS      kill a worker after MS milliseconds (default: 60000; 0 disables)
  --filter=PATTERN  run only tests whose full name matches the Lua pattern
  --jobs=N          max parallel nvim workers (default: cpu count)
  --shuffle         randomize test order
  --seed=N          seed used with --shuffle (default: time based)
  --setup=PATH      run a Lua script in each worker before any spec
  -h, --help        show this help

With no paths, runs the *_spec.lua files under ./spec.
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
