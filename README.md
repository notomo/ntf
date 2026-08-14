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
  --coverage[=FILE]    measure line coverage; write luacov.stats.out (or FILE) and print a summary
  --exclude-code=PATH  leave a file or directory out of the code that is measured and mutated (repeatable)
  -h, --help           show this help

With no paths, the *_spec.lua files under ./spec are used.

Usage: ntf list [options] [spec-file-or-dir...]

list the tests without running them

Options:
  --filter=PATTERN     run only tests whose full name matches the Lua pattern
  --global-hook=FILE   run a Lua module providing setup/teardown once around the whole run, in the launcher process
  --exclude-spec=PATH  skip a spec file or directory when discovering tests (repeatable)
  -h, --help           show this help

With no paths, the *_spec.lua files under ./spec are used.

Usage: ntf mutation [run] [options] [spec-file-or-dir...]

Commands:
  run (default)  mutate the covered code once the tests pass and score the mutants
  list           list the mutants with coverage, without scoring them
  baseline       work on the --config baseline: verify its entries, or write one

Options:
  --filter=PATTERN     run only tests whose full name matches the Lua pattern
  --global-hook=FILE   run a Lua module providing setup/teardown once around the whole run, in the launcher process
  --exclude-spec=PATH  skip a spec file or directory when discovering tests (repeatable)
  --timeout=MS         kill a worker after MS milliseconds (default: 60000; 0 disables)
  --jobs=N             max parallel nvim workers (default: cpu count)
  --test-hook=FILE     run a Lua module providing setup/teardown around each test, in its worker
  --exclude-code=PATH  leave a file or directory out of the code that is measured and mutated (repeatable)
  --target=PATH        restrict the mutated files to this file or directory
  --config=FILE        take the mutation policy from FILE: its required operators say which operators run at all, its baseline of known-equivalent mutants leaves the score, its exclude paths stay unmutated; exit non-zero when an entry matches nothing
  --strict[=LIST]      exit non-zero when any mutant is survived or no-coverage (LIST restricts the gate to a comma-separated subset)
  --verify-baseline    run the --config baseline entries instead of trusting them, in the same pass that scores every other mutant; exit non-zero when a test kills one
  --results=FILE       mutation results output path (default: ntf-mutation.json)
  -h, --help           show this help

With no paths, the *_spec.lua files under ./spec are used.

Usage: ntf mutation list [options] [spec-file-or-dir...]

list the mutants with coverage, without scoring them

Options:
  --filter=PATTERN     run only tests whose full name matches the Lua pattern
  --global-hook=FILE   run a Lua module providing setup/teardown once around the whole run, in the launcher process
  --exclude-spec=PATH  skip a spec file or directory when discovering tests (repeatable)
  --timeout=MS         kill a worker after MS milliseconds (default: 60000; 0 disables)
  --jobs=N             max parallel nvim workers (default: cpu count)
  --test-hook=FILE     run a Lua module providing setup/teardown around each test, in its worker
  --exclude-code=PATH  leave a file or directory out of the code that is measured and mutated (repeatable)
  --target=PATH        restrict the mutated files to this file or directory
  --config=FILE        take the mutation policy from FILE: its required operators say which operators run at all, its baseline of known-equivalent mutants leaves the score, its exclude paths stay unmutated; exit non-zero when an entry matches nothing
  -h, --help           show this help

With no paths, the *_spec.lua files under ./spec are used.

Usage: ntf mutation baseline [verify] [options] [spec-file-or-dir...]

Commands:
  verify (default)  run the baseline entries alone and fail any that a test can kill
  add               write the entry for one mutant into the baseline, leaving the tests unrun

Options:
  --filter=PATTERN     run only tests whose full name matches the Lua pattern
  --global-hook=FILE   run a Lua module providing setup/teardown once around the whole run, in the launcher process
  --exclude-spec=PATH  skip a spec file or directory when discovering tests (repeatable)
  --timeout=MS         kill a worker after MS milliseconds (default: 60000; 0 disables)
  --jobs=N             max parallel nvim workers (default: cpu count)
  --test-hook=FILE     run a Lua module providing setup/teardown around each test, in its worker
  --exclude-code=PATH  leave a file or directory out of the code that is measured and mutated (repeatable)
  --target=PATH        restrict the mutated files to this file or directory
  --config=FILE        take the mutation policy from FILE: its required operators say which operators run at all, its baseline of known-equivalent mutants leaves the score, its exclude paths stay unmutated; exit non-zero when an entry matches nothing
  -h, --help           show this help

With no paths, the *_spec.lua files under ./spec are used.

Usage: ntf mutation baseline add [options]

write the entry for one mutant into the baseline, leaving the tests unrun

Options:
  --config=FILE                   the mutation policy file to write the entry into, under its baseline
  --mutant=PATH:ROW:COL:OPERATOR  the mutant to write a baseline entry for, spelled as a report prints it
  --replacement=TEXT              what the mutant puts in place of the original, needed only when its position holds more than one of the operator's mutants
  --rationale=TEXT                why no test can detect the mutant, which is what a later judgement starts from
  --invariant-spec=NAME           full name of the test that fails once the rationale stops holding
  -h, --help                      show this help
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
