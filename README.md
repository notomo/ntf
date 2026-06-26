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

```lua
-- The test API is pulled from `require("ntf")` explicitly (no global injection).
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending
local before_each, after_each, finally = ntf.before_each, ntf.after_each, ntf.finally
local assert = ntf.assert

describe("group", function()
  local value
  before_each(function()
    value = 1
  end)
  after_each(function()
    value = nil
  end)

  it("does something", function()
    finally(function()
      -- runs when this test finishes, whether it passed or failed
    end)
    assert.equal(1, value)
  end)

  pending("not implemented yet")
end)
```
