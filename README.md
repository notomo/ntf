# ntf

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
local ntf = vim.api.nvim_get_runtime_file("bin/ntf", false)[1]
if ntf then
  vim.env.PATH = vim.fs.dirname(ntf) .. (vim.fn.has("win32") == 1 and ";" or ":") .. vim.env.PATH
end
```

## Usage

```
Usage: ntf [run] [options] [spec-file-or-dir...]

Commands:
  run (default)  run the tests and report the results
  list           list the tests without running them
  mutation       mutation-test the covered code

Options:
  --filter=PATTERN     run only tests whose full name matches the Lua pattern
  --global-hook=FILE   run a Lua module providing setup/teardown once around the whole run, in the launcher process
  --exclude-spec=PATH  skip a spec file or directory when discovering tests (repeatable)
  --timeout=MS         kill a worker after MS milliseconds (default: 60000; 0 disables)
  --jobs=N             max parallel nvim workers (default: cpu count)
  --test-hook=FILE     run a Lua module providing setup/teardown around each test, in its worker
  --coverage[=FILE]    measure line coverage; write the luacov.stats.out format to FILE (default: a cache file named for the working directory) and print a summary
  --exclude-code=PATH  leave a file or directory out of the code that is measured and mutated (repeatable)
  -h, --help           show this help

With no paths, the *_spec.lua files under ./spec are used.
```

`ntf CMD --help` prints the options of any other command. Hooks, coverage and
mutation testing are documented in [doc/ntf.txt](doc/ntf.txt).

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
