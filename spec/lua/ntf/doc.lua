vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.core.controller.args")
local plugin_name = vim.env.PLUGIN_NAME

local usage = args.usage()

local ntf_script = vim.fs.joinpath(vim.fn.getcwd(), "bin/ntf")

local cache_home = vim.fn.tempname()

--- @param cli_args string[]
--- @param opts { env: table<string,string>?, cwd: string? }? env is merged into the inherited one
local run_ntf = function(cli_args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ ntf_script }, cli_args)
  local env = vim.tbl_extend("force", { XDG_CACHE_HOME = cache_home }, opts.env or {})
  local result = vim.system(cmd, { env = env, cwd = opts.cwd }):wait()
  if result.code ~= 0 then
    error(("failed to run: %s\n%s"):format(table.concat(cmd, " "), result.stdout .. result.stderr))
  end
end

local example_path = ("./spec/lua/%s/example.lua"):format(plugin_name)
local example_spec = vim.fn.tempname() .. "_spec.lua"
vim.fn.writefile(vim.fn.readfile(example_path), example_spec)
run_ntf({ example_spec })

local doc_dir = ("./spec/lua/%s/doc"):format(plugin_name)

local test_hook_path = doc_dir .. "/test_hook.lua"
run_ntf({ "--test-hook=" .. test_hook_path, example_spec })
local test_hook_command = "ntf --test-hook=./" .. vim.fs.basename(test_hook_path)

local global_hook_path = doc_dir .. "/global_hook.lua"
run_ntf({ "--global-hook=" .. global_hook_path, example_spec })
local global_hook_command = "ntf --global-hook=./" .. vim.fs.basename(global_hook_path)

local debug_hook_path = doc_dir .. "/debug.lua"
local stub_dir = vim.fn.tempname()
vim.fn.mkdir(stub_dir, "p")
local stub = assert(io.open(stub_dir .. "/lldebugger.lua", "w"))
stub:write("return { start = function() end }\n")
stub:close()
run_ntf({
  "--test-hook=" .. debug_hook_path,
  "--jobs=1",
  "--filter=does something",
  example_spec,
}, { env = { LUA_PATH = stub_dir .. "/?.lua;;" } })
local debug_command = ("ntf --test-hook=./%s --jobs=1 --filter='the test name'"):format(
  vim.fs.basename(debug_hook_path)
)

local project_dir = vim.fn.tempname()
vim.fn.mkdir(vim.fs.joinpath(project_dir, "lua"), "p")
vim.fn.mkdir(vim.fs.joinpath(project_dir, "spec"), "p")
vim.fn.writefile({
  "local M = {}",
  "function M.is_positive(n)",
  "  return n > 0",
  "end",
  "return M",
}, vim.fs.joinpath(project_dir, "lua/mymod.lua"))
vim.fn.writefile({
  'local ntf = require("ntf")',
  'ntf.it("is false at the boundary", function()',
  '  ntf.assert.is_false(require("mymod").is_positive(0))',
  "end)",
}, vim.fs.joinpath(project_dir, "spec/mymod_spec.lua"))
vim.fn.mkdir(vim.fs.joinpath(project_dir, "lua/vendor"), "p")
vim.fn.writefile({
  "local M = {}",
  "function M.f()",
  "  return 1",
  "end",
  "return M",
}, vim.fs.joinpath(project_dir, "lua/vendor/dep.lua"))
vim.fn.writefile({
  "local M = {}",
  "function M.main(argv)",
  "  if #argv > 0 then",
  "    return 1",
  "  end",
  "  return 0",
  "end",
  "return M",
}, vim.fs.joinpath(project_dir, "lua/launcher.lua"))

run_ntf({ "--coverage=" .. vim.fn.tempname(), "spec" }, { cwd = project_dir })
local coverage_command = "ntf --coverage"

run_ntf({
  "--coverage=" .. vim.fn.tempname(),
  "--exclude-code=lua/vendor",
  "spec",
}, { cwd = project_dir })
local exclude_code_command = "ntf --coverage --exclude-code=lua/vendor --exclude-code=lua/mymod/test"

run_ntf({
  "--mutation=lua/mymod.lua",
  "--mutation-results=" .. vim.fn.tempname(),
  "spec",
}, { cwd = project_dir })
local mutation_command = "ntf --mutation"
local mutation_strict_command = "ntf --mutation --mutation-strict"

local mutation_config_path = doc_dir .. "/mutation_config.json"
vim.fn.writefile(vim.fn.readfile(mutation_config_path), vim.fs.joinpath(project_dir, "spec/mutation.json"))
run_ntf({
  "--mutation=lua/mymod.lua",
  "--mutation-results=" .. vim.fn.tempname(),
  "--mutation-config=spec/mutation.json",
  "--mutation-strict",
  "spec",
}, { cwd = project_dir })
local mutation_config_command = "ntf --mutation --mutation-config=spec/mutation.json"

run_ntf({
  "--mutation=lua/mymod.lua",
  "--mutation-results=" .. vim.fn.tempname(),
  "--mutation-config=spec/mutation.json",
  "--mutation-verify-baseline",
  "spec",
}, { cwd = project_dir })
local mutation_verify_baseline_command =
  "ntf --mutation --mutation-config=spec/mutation.json --mutation-verify-baseline"

run_ntf({
  "--mutation=lua/mymod.lua",
  "--mutation-results=" .. vim.fn.tempname(),
  "--mutation-matrix",
  "spec",
}, { cwd = project_dir })
local mutation_matrix_command = "ntf --mutation --mutation-matrix"

run_ntf({
  "--mutation",
  "--mutation-results=" .. vim.fn.tempname(),
  "--mutation-config=spec/mutation.json",
  "spec",
}, { cwd = project_dir })

local documented_flags = {} --- @type table<string, true> keyed by the `args.flags` token
for _, f in ipairs(args.flags) do
  documented_flags[f.name] = true
end
for _, command in ipairs({
  test_hook_command,
  global_hook_command,
  debug_command,
  coverage_command,
  exclude_code_command,
  mutation_command,
  mutation_strict_command,
  mutation_config_command,
  mutation_verify_baseline_command,
  mutation_matrix_command,
}) do
  for token in command:gmatch("%-%-[%w-]+") do
    if not documented_flags[token] then
      error(("not a documented flag: %s in `%s`"):format(token, command))
    end
  end
end

local setup_path = doc_dir .. "/setup.lua"
dofile(setup_path)
if vim.fn.exepath("ntf") == "" then
  error("setup snippet did not put ntf on PATH: " .. setup_path)
end

local doc_config = vim.json.decode(table.concat(vim.fn.readfile(vim.env.DOC_CONFIG), "\n"))

require("genvdoc").generate(plugin_name, {
  source = doc_config.source,
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
        return util.help_code_block_from_file(example_path, { language = "lua" })
      end,
    },
    {
      name = "HOOKS",
      body = function()
        return table.concat({
          [[
`--test-hook=FILE` loads the given Lua module in every worker (via `dofile`).
Each test runs in its own worker process, so the module's optional `setup` and
`teardown` functions run once per test — but outside everything the spec itself
defines: `setup` before the spec is built, `teardown` after the worker's test
has run. They are deliberately not named `before_each`/`after_each` — those are
spec hooks around the test body; `setup`/`teardown` bracket the whole worker
instead.]],
          util.help_code_block_from_file(test_hook_path, { language = "lua" }),
          util.help_code_block(test_hook_command, { language = "sh" }),
          [[
A relative path resolves against the working directory (the plugin under test).
An error raised while loading the module or from `setup` is reported as a load
error. A `teardown` error is reported too — as an error entry alongside the
worker's results, so it fails the run without discarding the results already
produced.

`--global-hook=FILE` takes a module with the same contract but runs it once in
the launcher process instead of in every worker: `setup` before any spec file is
loaded, `teardown` after all workers have finished. Use it for state shared by
the whole run — start a server once, build a fixture once — while `--test-hook`
remains the per-test bracket:]],
          util.help_code_block(global_hook_command, { language = "sh" }),
          [[
An error raised while loading the module or from its `setup` aborts the run
before any test starts. A `teardown` error is reported after the results, so it
fails the run without discarding them.

Because `setup` runs before the spec is built, it is the injection point for a
debugger: the code under test loads while the debugger is already attached. ntf
has no debugger dependency of its own:]],
          util.help_code_block_from_file(debug_hook_path, { language = "lua" }),
          util.help_code_block(debug_command, { language = "sh" }),
          [[
Tests run in parallel worker processes whose stdout ntf captures, so to actually
attach a debugger keep it to a single worker (`--jobs=1`, and narrow to one test
with `--filter`). Wiring the debugger transport itself is up to your module.]],
        }, "\n")
      end,
    },
    {
      name = "COVERAGE",
      body = function()
        return table.concat({
          [[
`--coverage` measures line coverage of the code under test while the specs run.
It measures every file under the working directory except the test tree: any
`*_spec.lua` file and the test directory the specs were found in (its top-level
directory under the working directory — `spec/` by default, but whatever path you
pass) are excluded, so anything sitting alongside the specs there (such as cloned
test dependencies) is left out too. A measured file no test executed still shows
up, at 0% (LuaCATS meta files are skipped: they never run by definition). It
needs no extra install: ntf sets a Lua line
hook in each worker, merges the per-worker counts, prints a short summary, and
writes a `luacov.stats.out` (override the path with `--coverage=FILE`):]],
          util.help_code_block(coverage_command, { language = "sh" }),
          [[
Not everything under the working directory is code you hold your tests to —
vendored third-party files, your own test helpers. `--exclude-code=PATH` leaves a
file or directory out of the code under test; repeat it for each one. It applies
to `--mutation` as well, since that measures the same code:]],
          util.help_code_block(exclude_code_command, { language = "sh" }),
          [[
The built-in summary is intentionally simple (its line classification is a
heuristic). For an authoritative or HTML report, point LuaCov — which ntf does
not depend on — at the same stats file:
>sh
  luarocks install luacov
  luacov          # reads luacov.stats.out -> luacov.report.out
<
Coverage forces the interpreter (`jit.off()`) in each worker so the line hook is
not skipped by the JIT, which makes a `--coverage` run slower than a plain one.]],
        }, "\n")
      end,
    },
    {
      name = "MUTATION TESTING",
      body = function()
        return table.concat({
          [[
`--mutation` measures how much of the covered code your tests actually pin down.
It first runs the specs as usual (a mutant means nothing against a failing suite,
so the run stops there if a test fails), then makes one small change at a time to
the code under test — swapping `==` for `~=`, `and` for `or`, `+` for `-`, `<` for
`<=`, flipping a boolean literal, dropping a `not`, bumping a number — and runs
the tests again. A mutant that makes a test fail is detected; one that leaves the
whole suite green is a hole in the tests, and is reported with the change it got
away with:]],
          util.help_code_block(mutation_command, { language = "sh" }),
          [[
Only the mutants a test can reach are run, using the same line coverage as
`--coverage` (which `--mutation` therefore always collects): a mutant on a line no
test executes is reported as uncovered rather than run. A mutant is run against
its covering tests one at a time, cheapest first, and the run stops at the first
test that detects it — in the same one-process-per-test isolation as a normal run.
A test that hangs on a mutant (an infinite loop) is killed and counts as detected.

The score is the share of detected mutants, counting an uncovered one as
undetected. `--mutation-strict` turns that into a gate, exiting non-zero when any
mutant survived or was left uncovered; `--mutation-strict=survived` (or
`=no_coverage`) gates only that category, so the bar can be raised in steps:]],
          util.help_code_block(mutation_strict_command, { language = "sh" }),
          [[
Stopping at the first detecting test keeps the run short, but it also means the
results only ever name one of a mutant's killers. `--mutation-matrix` runs the
remaining tests anyway and records every one that detects the mutant, which
answers the opposite question: not which code the tests miss, but which tests
the suite would not miss. A test that is never the sole killer of any mutant
detects nothing its siblings do not, and is reported as REDUNDANT:]],
          util.help_code_block(mutation_matrix_command, { language = "sh" }),
          [[
The verdict rests on knowing a mutant's whole killer set, so a mutant whose set
is cut short — by a test that hangs on it, or by a mutant the run could not
apply — is left out of the report. The flag never changes the score or the
`--mutation-strict` gate; it only fills in `killers` in the results file.

The cost is one run of the suite per covering test rather than per mutant.
`--mutation-matrix=N` bounds it by skipping the mutants more than N tests reach,
which are the ones with the most trials to run — but skipping them drops those
tests from the report rather than the mutants, since a test that only ever
reaches the hot path then appears in no killer set at all. Reach for `N` when a
whole matrix is genuinely too slow, not by default.

Read the report as a ranking to review, not a delete list. Redundancy is
measured against the mutants that exist today, and a test that duplicates
another one now may be the only one left holding a behaviour once the code
moves.

`--mutation=PATH` restricts the mutated files to one file or directory, which is
how you keep a run short: mutating everything means running the suite once per
mutant. The full result — every mutant, its position, and what it became — is
written to `ntf-mutation.json` (override with `--mutation-results=FILE`), which
|ntf.mutation.decorate()| reads back to mark the survivors in a buffer.

Two limits are worth knowing. A mutant is spliced in when the module is
`require`d, so a file the specs load through `dofile`/`loadfile` instead keeps
its original source and is reported as not applied — never as a survivor. And
some mutants are equivalent to the code they replace, which no test can detect.
Rather than re-reviewing those survivors on every run, record each one — with
the reason — in the `baseline` of a config file and pass it with
`--mutation-config=FILE`:]],
          util.help_code_block_from_file(mutation_config_path, { language = "json" }),
          util.help_code_block(mutation_config_command, { language = "sh" }),
          [[
The file carries the whole mutation policy, one section per kind of judgement —
`exclude` is the second, covered below — and either section may be left out.

A listed `baseline` mutant is reported as equivalent and leaves the score, which
can then reach 100 and be held there with `--mutation-strict`. An entry is
copied from the survivor's record in the results file (`path` relative to the
working directory, `col`, `operator`, `original`, `replacement`) plus the exact
text of the mutated `line`; ntf only reads the file, so keep it in the
repository and edit it by hand. An entry names its mutant by the line's text
rather than its number: it keeps matching while the code merely moves, and when
the marked line itself changes the run fails, listing the entry as LOST — the
judgement has to be made again, by fixing the entry or deleting it. The
`rationale` is required; it is what that later judgement starts from.

A rationale usually rests on a fact from somewhere else — what the callers pass,
what shape another module hands over, what the runtime does with a value. That
fact can stop holding without the marked line moving, and then the entry keeps
the mutant out of the score for a reason that is no longer true. Name the test
that pins the fact in the optional `invariant_spec`, by its full name, and ntf
fails the run — reporting the entry as UNPINNED BASELINE — when no test of that
name passed. Renaming or deleting the test then has to be answered for, instead
of quietly unmooring the rationale.

An entry is only ever trusted, not checked: a mutant a new test would now detect
stays out of the score behind a mark that no longer holds. `--mutation-verify-baseline`
runs the listed mutants instead of trusting them and exits non-zero, reporting
each as BASELINE KILLABLE, when a test kills one — the mirror of LOST, catching a
stale judgement the code line never gave away. Run it after editing the baseline:]],
          util.help_code_block(mutation_verify_baseline_command, { language = "sh" }),
          [[
A baseline answers for one mutant. Some files instead have to stay out of the
run whole: code that only ever executes in a process no spec drives, where every
mutant comes back uncovered rather than detected. `--exclude-code=PATH` does
that, but it takes no reason, so such a list grows quietly and outlives what put
each path on it. The config file's `exclude` section — shown above — is the same
exclusion with a required `rationale` per path, and it fails the run — reporting
UNUSED EXCLUDE — when an entry covers none of the measurable files, so a path
that has been renamed or already covered by a broader entry has to be answered
for.

The two are not interchangeable. `--exclude-code` drops a path from the code
under test altogether, which is what a vendored copy wants; an `exclude` entry
drops it from the mutation only, and leaves `--coverage` still measuring it.]],
        }, "\n")
      end,
    },
    {
      name = "HIGHLIGHT GROUPS",
      body = function(ctx)
        local files = {
          ("./lua/%s/coverage/highlight_group.lua"):format(plugin_name),
          ("./lua/%s/mutation/highlight_group.lua"):format(plugin_name),
        }
        local sections = vim
          .iter(files)
          :map(util.extract_documented_table)
          :flatten()
          :map(function(hl_group)
            return util.help_tagged(ctx, hl_group.key, "hl-" .. hl_group.key)
              .. util.indent(hl_group.document, 2)
              .. "\n"
          end)
          :totable()
        return vim.trim(table.concat(sections, "\n"))
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
        if node.declaration.module == "ntf.assert.meta" then
          node.declaration.module = "ntf.assert"
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
  local example = util.read_all(example_path)
  local setup = util.read_all(setup_path)

  local content = ([[
# %s

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
%s```

## Usage

```
%s
```

## Writing specs

```lua
%s```
]]):format(plugin_name, setup, usage, example)

  util.write("README.md", content)
end
gen_readme()
