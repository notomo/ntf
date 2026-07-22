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
Usage: ntf [options] [spec-file-or-dir...]

Options:
  --timeout=MS              kill a worker after MS milliseconds (default: 60000; 0 disables)
  --filter=PATTERN          run only tests whose full name matches the Lua pattern
  --list                    list the tests without running them (with --mutation, run the tests and list the mutants with coverage)
  --jobs=N                  max parallel nvim workers (default: cpu count)
  --test-hook=FILE          run a Lua module providing setup/teardown around each test, in its worker
  --global-hook=FILE        run a Lua module providing setup/teardown once around the whole run, in the launcher process
  --exclude-code=PATH       leave a file or directory out of the code --coverage measures and --mutation mutates (repeatable)
  --exclude-spec=PATH       skip a spec file or directory when discovering tests (repeatable)
  --coverage[=FILE]         measure line coverage; write luacov.stats.out (or FILE) and print a summary
  --mutation[=PATH]         mutation-test the covered code (only under PATH, if given) once the tests pass
  --mutation-strict[=LIST]  exit non-zero when any mutant is survived or no-coverage (LIST restricts the gate to a comma-separated subset)
  --mutation-baseline=FILE  leave the known-equivalent mutants listed in FILE out of the score; exit non-zero when an entry matches nothing
  --mutation-results=FILE   mutation results output path (default: ntf-mutation.json)
  -h, --help                show this help

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
