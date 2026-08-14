vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.core.controller.args")
local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")
local report = require("ntf.core.mutation.report")
local config = require("ntf.core.mutation.config")
local plugin_name = vim.env.PLUGIN_NAME

--- @type string[] every leaf command, of which the docs show only the root's usage
local command_ids =
  { "run", "list", "mutation.run", "mutation.list", "mutation.baseline.verify", "mutation.baseline.add" }
for _, command_id in ipairs(command_ids) do
  if args.usage(command_id) == "" then
    error("no usage for the command: " .. command_id)
  end
end

local usage = args.usage("run")

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
vim.fn.writefile({
  'local ntf = require("ntf")',
  'ntf.it("runs the built command end to end", function()',
  '  ntf.assert.is_true(require("mymod").is_positive(1))',
  "end)",
}, vim.fs.joinpath(project_dir, "spec/cli_spec.lua"))
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

run_ntf({ "list", "spec" }, { cwd = project_dir })
local list_command = "ntf list"

run_ntf({
  "mutation",
  "--target=lua/mymod.lua",
  "--results=" .. vim.fn.tempname(),
  "spec",
}, { cwd = project_dir })
local mutation_command = "ntf mutation"
local mutation_strict_command = "ntf mutation --strict"

run_ntf({ "mutation", "list", "--target=lua/mymod.lua", "spec" }, { cwd = project_dir })
local mutation_list_command = "ntf mutation list"

local mutation_config_path = doc_dir .. "/mutation_config.json"
local mutation_operators_path = doc_dir .. "/mutation_operators.json"
local project_config_path = vim.fs.joinpath(project_dir, "spec/mutation.json")

vim.fn.writefile(vim.fn.readfile(mutation_operators_path), vim.fs.joinpath(project_dir, "spec/operators.json"))
run_ntf({
  "mutation",
  "--target=lua/mymod.lua",
  "--results=" .. vim.fn.tempname(),
  "--config=spec/operators.json",
  "spec",
}, { cwd = project_dir })

local rationale = "the specs only ever ask about 0, whose answer the shifted boundary leaves false"
local invariant_spec = "is false at the boundary"
vim.fn.writefile({ "{", '  "version": 1,', '  "operators": "all"', "}" }, project_config_path)
run_ntf({
  "mutation",
  "baseline",
  "add",
  "--config=spec/mutation.json",
  "--mutant=lua/mymod.lua:3:13:perturb-number",
  "--rationale=" .. rationale,
  "--invariant-spec=" .. invariant_spec,
}, { cwd = project_dir })
local mutation_baseline_add_command = table.concat({
  "ntf mutation baseline add --config=spec/mutation.json \\",
  "  --mutant=lua/mymod.lua:3:13:perturb-number \\",
  ("  --rationale='%s' \\"):format(rationale),
  ("  --invariant-spec='%s'"):format(invariant_spec),
}, "\n")

local written = vim.json.decode(table.concat(vim.fn.readfile(project_config_path), "\n"))
local documented = vim.json.decode(table.concat(vim.fn.readfile(mutation_config_path), "\n"))
if not vim.deep_equal(written.baseline, documented.baseline) then
  error(
    ("the documented config's baseline is not what `baseline add` writes: %s"):format(vim.inspect(written.baseline))
  )
end

vim.fn.writefile(vim.fn.readfile(mutation_config_path), project_config_path)
run_ntf({
  "mutation",
  "--target=lua/mymod.lua",
  "--results=" .. vim.fn.tempname(),
  "--config=spec/mutation.json",
  "--strict",
  "spec",
}, { cwd = project_dir })
local mutation_config_command = "ntf mutation --config=spec/mutation.json"

run_ntf({
  "mutation",
  "baseline",
  "verify",
  "--target=lua/mymod.lua",
  "--config=spec/mutation.json",
  "spec",
}, { cwd = project_dir })
local mutation_verify_baseline_command = "ntf mutation baseline verify --config=spec/mutation.json"

run_ntf({
  "mutation",
  "--target=lua/mymod.lua",
  "--results=" .. vim.fn.tempname(),
  "--config=spec/mutation.json",
  "--strict",
  "--verify-baseline",
  "spec",
}, { cwd = project_dir })
local mutation_verify_baseline_with_score_command =
  "ntf mutation --config=spec/mutation.json --strict --verify-baseline"

run_ntf({
  "mutation",
  "--results=" .. vim.fn.tempname(),
  "--config=spec/mutation.json",
  "spec",
}, { cwd = project_dir })

for _, command in ipairs({
  test_hook_command,
  global_hook_command,
  debug_command,
  coverage_command,
  exclude_code_command,
  list_command,
  mutation_command,
  mutation_strict_command,
  mutation_list_command,
  mutation_config_command,
  mutation_baseline_add_command,
  mutation_verify_baseline_command,
  mutation_verify_baseline_with_score_command,
}) do
  local words = vim.split(command, " ", { plain = true })
  local chain = args.resolve(vim.list_slice(words, 2))
  local documented_flags = {} --- @type table<string, true> keyed by the token the command documents
  for _, f in ipairs(chain[#chain].flags) do
    documented_flags[f.name] = true
  end
  for token in command:gmatch("%-%-[%w-]+") do
    if not documented_flags[token] then
      error(("not a flag of `%s`: %s"):format(command, token))
    end
  end
end

--- @param entries { label: string, description: string }[]
--- @param width integer the document width a line has to fit in
--- @return string # a two-column list, the descriptions aligned past the widest label
local table_block = function(entries, width)
  local label_width = 0
  for _, entry in ipairs(entries) do
    label_width = math.max(label_width, #entry.label)
  end
  local lines = {}
  for _, entry in ipairs(entries) do
    local line = ("%-" .. label_width .. "s  %s"):format(entry.label, entry.description)
    local indent = 2
    if #line + indent > width then
      error(("too long for the document width: %s"):format(line))
    end
    table.insert(lines, line)
  end
  return util.help_code_block(table.concat(lines, "\n"))
end

--- @param names string[] the keys the document spells out
--- @param tbl table the value they have to be exactly the keys of
--- @param what string what the document calls them
local assert_keys = function(names, tbl, what)
  local got = vim.tbl_keys(tbl)
  table.sort(got)
  local want = vim.list_extend({}, names)
  table.sort(want)
  if not vim.deep_equal(want, got) then
    error(("the %s the example file carries are not the documented ones: %s"):format(what, vim.inspect(got)))
  end
end

-- WHY: an implementation that gains a name the document has never heard of is
-- what a check against the document's own example cannot see, so the names come
-- from the tables the code itself works from.
-- NOT: listing the names twice and comparing the document to a copy of itself.
--- @param names string[] the names the document spells out, in the order it lists them
--- @param in_use string[] the names the implementation works from
--- @param what string what the document calls them
local assert_names = function(names, in_use, what)
  if not vim.deep_equal(names, in_use) then
    error(("the %s the document spells are not the ones in use: %s"):format(what, vim.inspect(in_use)))
  end
end

--- @param names string[]
--- @return string[] # a sorted copy, for names no order is meant to be read into
local sorted = function(names)
  local copy = vim.list_extend({}, names)
  table.sort(copy)
  return copy
end

--- @param entries { label: string, description: string }[]
--- @return string[]
local labels_of = function(entries)
  return vim
    .iter(entries)
    :map(function(entry)
      return entry.label
    end)
    :totable()
end

--- @type { label: string, description: string }[] what a test has to do to detect each operator's mutant, in the order the document lists them
local operator_descriptions = {
  { label = "swap-relational", description = "a test has to exercise the boundary value the two disagree on" },
  { label = "swap-logical", description = "a test has to reach operands the two connectives disagree on" },
  { label = "swap-arithmetic", description = "a test has to exercise a right operand the two disagree on" },
  { label = "swap-boolean", description = "a test has to depend on the value, not merely execute the line" },
  { label = "drop-not", description = "a test has to reach the branch the negation decides" },
  { label = "drop-negation", description = "a test has to exercise a nonzero operand and depend on its sign" },
  { label = "perturb-number", description = "a test has to depend on the exact value, not on its being non-zero" },
  { label = "perturb-length", description = "a test has to depend on the exact count, not on its being non-zero" },
  { label = "force-branch", description = "each side needs a test; a loop is only forced to the outcome that exits" },
  { label = "drop-call", description = "a test has to observe what the call does, not merely reach its line" },
  { label = "drop-assignment", description = "a test has to observe what the assignment stores, not merely reach it" },
  {
    label = "drop-return-value",
    description = "a test has to depend on what the function answers, not merely reach it",
  },
}
assert_names(
  labels_of(operator_descriptions),
  vim.tbl_map(function(operator)
    return operator.name
  end, operators.operators),
  "operator names"
)
local description_by_operator = {}
for _, entry in ipairs(operator_descriptions) do
  description_by_operator[entry.label] = entry.description
end

--- @param width integer the document width a line has to fit in
--- @return string # every operator with the change its example gets and what detects it
local operator_list = function(width)
  local name_width = 0
  for _, operator in ipairs(operators.operators) do
    name_width = math.max(name_width, #operator.name)
  end
  local blocks = {}
  for _, operator in ipairs(operators.operators) do
    local sites = operators.enumerate(operator.example)
    if #sites == 0 then
      error(("no site in the example of %s: %s"):format(operator.name, operator.example))
    end
    local lines = {}
    local name = operator.name
    for _, site in ipairs(sites) do
      local mutated = assert(splice.apply(operator.example, site), "example does not match its site")
      table.insert(lines, ("%-" .. name_width .. "s %s -> %s"):format(name, operator.example, mutated))
      name = ""
    end
    table.insert(lines, "    " .. description_by_operator[operator.name])

    local indent = 2
    for _, line in ipairs(lines) do
      if #line + indent > width then
        error(("too long for the document width: %s"):format(line))
      end
    end
    table.insert(blocks, table.concat(lines, "\n"))
  end
  return table.concat(blocks, "\n\n")
end

--- @type { label: string, description: string }[] the config file's sections
local config_sections = {
  { label = "version", description = "the policy file format, currently 1 (required)" },
  { label = "operators", description = "which operators produce mutants at all (required)" },
  { label = "baseline", description = "the mutants judged impossible to kill" },
  { label = "exclude", description = "files whose mutants the run leaves out" },
  { label = "exclude_spec", description = "specs never picked as a mutant's trial" },
}
local sections_by_key = {}
for _, section in ipairs(config.sections) do
  sections_by_key[section.key] = section
end
assert_names(
  labels_of(config_sections),
  vim.list_extend(
    { "version", "operators" },
    vim.tbl_map(function(section)
      return section.key
    end, config.sections)
  ),
  "config sections"
)
assert_keys(labels_of(config_sections), documented, "config sections")

--- @type { label: string, description: string }[] what a baseline entry names its mutant by
local baseline_fields = {
  { label = "path", description = "the mutated file, relative to the working directory" },
  { label = "col", description = "the column the mutant starts at" },
  { label = "operator", description = "the change, named as the report names it" },
  { label = "original", description = "what the mutant replaces" },
  { label = "replacement", description = "what it puts there" },
  { label = "line", description = "the text of the line, matched instead of a row" },
  { label = "rationale", description = "why no test can detect it (required)" },
  { label = "invariant_spec", description = "full name of the test the rationale rests on" },
}
assert_names(labels_of(baseline_fields), sections_by_key.baseline.fields, "baseline entry fields")
assert_keys(labels_of(baseline_fields), documented.baseline[1], "baseline entry fields")

--- @type { label: string, description: string }[] what an exclude entry answers for
local exclude_fields = {
  { label = "path", description = "the file the entry answers for" },
  { label = "operators", description = '"all", or the operator names to leave out (required)' },
  { label = "rationale", description = "why its mutants are left out (required)" },
}
assert_names(labels_of(exclude_fields), sections_by_key.exclude.fields, "exclude entry fields")
assert_keys(labels_of(exclude_fields), documented.exclude[1], "exclude entry fields")

--- @type { label: string, description: string }[] what an exclude_spec entry answers for
local exclude_spec_fields = {
  { label = "path", description = "the spec the entry answers for" },
  { label = "rationale", description = "why it is never a trial (required)" },
}
assert_names(labels_of(exclude_spec_fields), sections_by_key.exclude_spec.fields, "exclude_spec entry fields")
assert_keys(labels_of(exclude_spec_fields), documented.exclude_spec[1], "exclude_spec entry fields")

--- @type { label: string, description: string }[] the lines a mutation run lists a judgement under
local report_labels = {
  { label = "SURVIVED", description = "no test noticed the change" },
  { label = "NO COVERAGE", description = "no test reaches the line, so it was never run" },
  { label = "NOT APPLIED", description = "the file was not `require`d, so nothing changed" },
  { label = "BASELINE KILLABLE", description = "a baseline entry a test kills, named with the test" },
  { label = "LOST BASELINE", description = "a baseline entry whose `line` is no longer there" },
  { label = "UNPINNED BASELINE", description = "its `invariant_spec` names no test that passed" },
  { label = "UNUSED EXCLUDE", description = "an `exclude` entry covering no measurable file" },
  { label = "UNUSED EXCLUDE SPEC", description = "an `exclude_spec` entry covering no spec file" },
}
local listed_in_use = vim.tbl_values(report.entry_labels)
for _, listed in pairs(report.listed) do
  table.insert(listed_in_use, listed.label)
end
assert_names(sorted(labels_of(report_labels)), sorted(listed_in_use), "report labels")

--- @type { label: string, description: string }[] the statuses the count line tallies
local count_labels = {
  { label = "killed", description = "detected: a test failed on the mutant" },
  { label = "timeout", description = "detected: a test hung and its worker was killed" },
  { label = "survived", description = "undetected: the tests stayed green" },
  { label = "no coverage", description = "undetected: no test reached the line" },
  { label = "not applied", description = "the mutant never landed, so it says nothing" },
  { label = "equivalent", description = "a `baseline` entry, left out of the score" },
  { label = "excluded", description = "an `exclude` entry's operator, out of the score" },
  { label = "unadopted", description = "an operator `operators` does not take" },
  { label = "baseline killable", description = "a `baseline` entry a test killed" },
}
assert_names(
  labels_of(count_labels),
  vim.tbl_map(function(entry)
    return entry.label
  end, report.count_labels),
  "count line labels"
)

--- @param row integer
--- @param status string
local mutation_record = function(row, status)
  return {
    mutant = {
      path = "lua/mymod.lua",
      operator = "swap-relational",
      row = row,
      col = 13,
      end_row = row,
      end_col = 14,
      start_byte = 0,
      end_byte = 1,
      original = ">",
      replacement = ">=",
    },
    status = status,
  }
end

local baseline_entry = {
  path = "lua/mymod.lua",
  operator = "perturb-number",
  original = "0",
  replacement = "1",
  line = "  return n > 0",
  invariant_spec = "is false at the boundary",
}
-- WHY: the labels above are the report's own words, so one summary holding every
-- judgement at once is what says they are still spelled that way.
-- NOT: reading them out of the module, which says nothing about the output.
local reported = report.summary({
  records = {
    mutation_record(1, "survived"),
    mutation_record(2, "no_coverage"),
    mutation_record(3, "not_applied"),
    mutation_record(4, "baseline_killable"),
  },
  counts = {
    killed = 1,
    timeout = 1,
    survived = 1,
    no_coverage = 1,
    not_applied = 1,
    equivalent = 1,
    excluded = 1,
    unadopted = 1,
    baseline_killable = 1,
  },
  score = 40,
  lost = { baseline_entry },
  unpinned = { baseline_entry },
  unused_excludes = { { path = "lua/launcher.lua" } },
  unused_spec_excludes = { { path = "spec/cli_spec.lua" } },
}, nil, { color = false, elapsed = 1.0 })
for _, entry in ipairs(vim.list_extend(vim.list_extend({}, report_labels), count_labels)) do
  if not reported:find(entry.label, 1, true) then
    error(("no run prints the documented label: %s\n%s"):format(entry.label, reported))
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
        return table.concat({
          [[
ntf takes a command. `run` runs the tests and is what a bare `ntf` means, `list`
lists them without running them, and `mutation` mutation-tests the covered code
with commands of its own. A command takes exactly the options it can act on and
rejects the rest.]],
          util.help_code_block(usage),
          [[
- `ntf CMD --help` prints the options of any other command, such as
  `ntf mutation --help` or `ntf mutation baseline add --help`.
- Only leading tokens name a command, so a path is never taken for one:
  `ntf run list` is how you name a path that reads like a command.
- A command that leaves the tests unrun takes no path at all and says so in its
  usage line, `mutation baseline add` being the one.
- |ntf-HOOKS|, |ntf-COVERAGE| and |ntf-MUTATION-TESTING| cover the rest.]],
        }, "\n")
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
      body = function(ctx)
        return table.concat({
          [[
A hook module returns an optional `setup` and an optional `teardown`. Which
process runs them, and how often, is what the two flags differ in.]],
          "\n" .. util.help_tagged(ctx, "--test-hook=FILE", "ntf-hook-test"),
          [[
Loaded in every worker (via `dofile`). Each test runs in its own worker, so the
functions run once per test, outside everything the spec itself defines:
`setup` before the spec is built, `teardown` after the worker's test has run.
(`before_each`/`after_each` bracket the test body; these bracket the worker.)]],
          util.help_code_block_from_file(test_hook_path, { language = "lua" }),
          util.help_code_block(test_hook_command, { language = "sh" }),
          [[
- A relative path resolves against the working directory (the plugin under
  test).
- An error while loading the module, or from `setup`, is reported as a load
  error.
- A `teardown` error is reported as an error entry alongside the worker's
  results, so it fails the run without discarding what was produced.]],
          "\n" .. util.help_tagged(ctx, "--global-hook=FILE", "ntf-hook-global"),
          [[
The same module contract, run once in the launcher process instead of in every
worker: `setup` before any spec file is loaded, `teardown` after all workers
have finished. Use it for state shared by the whole run — start a server once,
build a fixture once — while `--test-hook` remains the per-test bracket.]],
          util.help_code_block(global_hook_command, { language = "sh" }),
          [[
- An error while loading the module, or from its `setup`, aborts the run before
  any test starts.
- A `teardown` error is reported after the results, and fails the run without
  discarding them.]],
          "\n" .. util.help_tagged(ctx, "Attaching a debugger", "ntf-hook-debug"),
          [[
Because `setup` runs before the spec is built, it is where a debugger attaches:
the code under test then loads with the debugger already on. ntf has no
debugger dependency of its own.]],
          util.help_code_block_from_file(debug_hook_path, { language = "lua" }),
          util.help_code_block(debug_command, { language = "sh" }),
          [[
Worker stdout is captured, so keep it to a single worker (`--jobs=1`) and
narrow to one test (`--filter`). Wiring the debugger transport itself is up to
your module.]],
        }, "\n")
      end,
    },
    {
      name = "COVERAGE",
      body = function()
        return table.concat({
          [[
`--coverage` measures line coverage of the code under test while the specs run.
It needs no extra install: ntf sets a Lua line hook in each worker, merges the
per-worker counts, prints a short summary, and writes a `luacov.stats.out`
(override the path with `--coverage=FILE`):]],
          util.help_code_block(coverage_command, { language = "sh" }),
          [[
What it measures:

- every file under the working directory, except the test tree: any
  `*_spec.lua` file and the directory the specs were found in (`spec/` by
  default, but whatever path you pass), so anything sitting alongside the specs
  there — cloned test dependencies, say — is left out too
- a measured file no test executed, which shows up at 0%
- but never a LuaCATS meta file, which by definition never runs

Not everything under the working directory is code you hold your tests to —
vendored third-party files, your own test helpers. `--exclude-code=PATH` leaves a
file or directory out of the code under test; repeat it for each one. The
`mutation` commands take it too, since they measure the same code:]],
          util.help_code_block(exclude_code_command, { language = "sh" }),
          [[
The built-in summary is intentionally simple (its line classification is a
heuristic). For an authoritative or HTML report, point LuaCov — which ntf does
not depend on — at the same stats file:
>sh
  luarocks install luacov
  luacov          # reads luacov.stats.out -> luacov.report.out
<
A `--coverage` run is slower than a plain one: the line hook has to be reached
on every line.]],
        }, "\n")
      end,
    },
    {
      name = "MUTATION TESTING",
      body = function()
        return table.concat({
          [[
`ntf mutation` measures how much of the covered code your tests actually pin
down. It first runs the specs as usual — a mutant means nothing against a
failing suite, so the run stops there if a test fails — then makes one small
change at a time to the code under test and runs the tests again. A mutant that
makes a test fail is detected; one that leaves the whole suite green is a hole
in the tests, and is reported with the change it got away with:]],
          util.help_code_block(mutation_command, { language = "sh" }),
          [[
- Each kind of change is an operator: |ntf-MUTATION-OPERATORS| lists them, and
  the `operators` of |ntf-MUTATION-CONFIG| says which of them a run takes.
- Only the mutants a test can reach are run. The mutation commands always
  collect the same line coverage as `--coverage`, and a mutant on a line no
  test executes is reported NO COVERAGE instead of being run.
- A mutant is run against the tests that reach it, in the same
  one-process-per-test isolation as a normal run, and stops at the first test
  that detects it. A test that hangs on a mutant is killed and counts as
  detected.
- The score is the share of detected mutants, counting an uncovered one as
  undetected.
- `--target=PATH` restricts the mutated files to one file or directory, which
  is how you keep a run short: mutating everything means running the suite once
  per mutant.
- The full result — every mutant, its position, and what it became — is written
  to `ntf-mutation.json` (override with `--results=FILE`), which
  |ntf.mutation.decorate()| reads back to mark the survivors in a buffer.
- A mutant is spliced in when the module is `require`d, so a file the specs
  load through `dofile`/`loadfile` keeps its original source and is reported
  NOT APPLIED — never as a survivor.

`--strict` turns the score into a gate, exiting non-zero when any mutant
survived or was left uncovered. `--strict=survived` (or `=no_coverage`) gates
only that category, so the bar can be raised in steps:]],
          util.help_code_block(mutation_strict_command, { language = "sh" }),
          [[
To see what a run would cover before paying for it, `ntf mutation list` runs
the tests once and lists the mutants with the number of tests that reach each:]],
          util.help_code_block(mutation_list_command, { language = "sh" }),
        }, "\n")
      end,
    },
    {
      name = "MUTATION OPERATORS",
      body = function(ctx)
        return table.concat({
          [[
An operator is one kind of change. A mutant is reported under its operator's
name, and written into a baseline entry under it too. A name is a verb and what
it acts on, and the verbs are a closed set: `swap-` puts a sibling of the same
kind in place of the original, `drop-` takes something out and leaves what
surrounded it, `force-` pins a decision to one outcome, and `perturb-` shifts a
value by one. Each is shown here with the change its own example gets, and with
what a test has to do to detect it:]],
          util.help_code_block(operator_list(ctx.width)),
        }, "\n")
      end,
    },
    {
      name = "MUTATION CONFIG",
      body = function(ctx)
        return table.concat({
          [[
Every judgement a project makes about its mutation lives in one policy file,
passed with `--config=FILE`:]],
          util.help_code_block_from_file(mutation_config_path, { language = "json" }),
          util.help_code_block(mutation_config_command, { language = "sh" }),
          [[
One section per kind of judgement, of which only the first two are required:]],
          table_block(config_sections, ctx.width),
          [[
`operators` has no default because no default can say for a project which
operators it holds its tests to:

- `"all"` takes every operator, including the ones a later ntf adds — the right
  answer for a project that upgrades ntf and its own tests together.
- An array of names instead pins the set:
]],
          util.help_code_block_from_file(mutation_operators_path, { language = "json" }),
          [[
  An operator added upstream then reaches the run only once its name is written
  here, so upgrading ntf does not turn a green gate red with survivors nobody
  asked for. Until then its mutants are counted `unadopted` and left out of the
  score.
- A name no operator answers to is rejected before the tests run: a set that
  runs less than it says is the one mistake this file must not keep to itself.

The other two sections are |ntf-MUTATION-BASELINE| and |ntf-MUTATION-EXCLUDE|.]],
        }, "\n")
      end,
    },
    {
      name = "MUTATION BASELINE",
      body = function(ctx)
        return table.concat({
          [[
Some mutants are equivalent to the code they replace, which no test can detect.
Rather than re-reviewing those survivors on every run, record each one — with
the reason — in the `baseline` section shown in |ntf-MUTATION-CONFIG|. A listed
mutant is reported `equivalent` and leaves the score, which can then reach 100
and be held there with `--strict`.

An entry names its mutant with the report's own words for it:]],
          table_block(baseline_fields, ctx.width),
          [[
So `ntf mutation baseline add` writes the entry for you. It takes the mutant as
the report spells it and the judgement you have to supply, and runs no test —
what it writes is the claim that no test can tell the difference:]],
          util.help_code_block(mutation_baseline_add_command, { language = "sh" }),
          [[
- Every report spells a mutant as `PATH:ROW:COL:OPERATOR`, the same name
  `ntf mutation list` prints and the one `--mutant` takes, so naming one is a
  copy rather than a translation.
- `--replacement` is only needed where a single position holds more than one of
  that operator's mutants — the forced branch, which has one per outcome. Such
  a position is answered with the replacements to choose from rather than
  guessed at.
- The file stays a plain document written in one shape, so editing it by hand
  remains first-class.

An entry is otherwise only ever trusted, not checked: a mutant a new test would
now detect stays out of the score behind a mark that no longer holds.
`ntf mutation baseline verify` runs the listed mutants instead of trusting
them, reporting BASELINE KILLABLE with the test that did it and exiting
non-zero. It leaves every other mutant unrun, scoring nothing and writing no
results file, which is what you want right after editing the baseline:]],
          util.help_code_block(mutation_verify_baseline_command, { language = "sh" }),
          [[
A kill has to repeat before it counts, so a test that fails for reasons of its
own does not condemn an entry. `--verify-baseline` asks the same question of a
scoring run, verifying the entries in the same pass that scores the rest, so a
gate that wants both answers pays for one run of the suite instead of two:]],
          util.help_code_block(mutation_verify_baseline_with_score_command, { language = "sh" }),
          [[
Two report lines answer for an entry that has gone stale, and both fail the
run: LOST BASELINE, once the `line` it marks is no longer there, and UNPINNED
BASELINE, once no test named by `invariant_spec` passes. A rationale usually
rests on a fact from somewhere else — what the callers pass, what shape another
module hands over, what the runtime does with a value — and that fact can stop
holding without the marked line moving. Naming the test that pins it is what
makes renaming or deleting that test something to answer for, instead of
quietly unmooring the rationale.]],
        }, "\n")
      end,
    },
    {
      name = "MUTATION EXCLUDE",
      body = function(ctx)
        return table.concat({
          [[
A baseline entry answers for one mutant. A whole file, or a whole spec, is left
out in one of four ways, which are not interchangeable:]],
          table_block({
            {
              label = "--exclude-code=PATH",
              description = "neither measured nor mutated; takes no reason",
            },
            {
              label = "exclude (config)",
              description = "unmutated only; `--coverage` still measures it",
            },
            {
              label = "--exclude-spec=PATH",
              description = "the spec is not discovered, so it never runs",
            },
            {
              label = "exclude_spec (config)",
              description = "the spec runs, but is never a mutant's trial",
            },
          }, ctx.width),
          [[
The flags are the blunt forms: they take no rationale, so such a list grows
quietly and outlives what put each path on it. `--exclude-code` is still what a
vendored copy wants, since it is not code you hold your tests to at all. A gate
built on `--exclude-spec` has to run the suite a second time to cover what it
dropped.

The `exclude` section is for code that only ever executes in a process no spec
drives, where every mutant comes back uncovered rather than detected:]],
          table_block(exclude_fields, ctx.width),
          [[
Leaving a whole file out is the widest judgement the file can carry, so an
entry spells how much of it is meant:

- `"all"` names the whole file.
- An array of operator names leaves only those operators' mutants out — the
  file stays in the run, and they are reported `excluded` and, like an
  equivalent one, outside the score. That is the entry to write while a file's
  tests are still too coarse for one operator but answer for the rest, and it
  holds while the code is edited, where a baseline entry per surviving mutant
  would go LOST BASELINE on the first move.

The `exclude_spec` section answers for a test rather than for a file under
test:]],
          table_block(exclude_spec_fields, ctx.width),
          [[
A mutant is run against the tests that reach it, so an end-to-end spec — one
that drives the whole CLI, or a real editor — is picked as a trial for most of
the code and pays a full run each time to reach what a unit spec already
reaches. Listing its path keeps it out of every trial, and out of the coverage
that decides which mutants are covered at all, so a mutant only it reaches is
reported NO COVERAGE. It still runs with the rest of the suite, and the run
still stops when it fails, which is what lets one mutation run stand in for a
plain test run in CI. It takes no `operators`: it names a spec, not a file
mutants are enumerated from.

Both sections fail the run — UNUSED EXCLUDE and UNUSED EXCLUDE SPEC — when an
entry covers nothing, so a path that has been renamed, or is already covered by
a broader entry, has to be answered for.]],
        }, "\n")
      end,
    },
    {
      name = "MUTATION REPORT",
      body = function(ctx)
        return table.concat({
          [[
A mutation run prints one line per judgement it wants answered, each naming the
mutant as `PATH:ROW:COL:OPERATOR` or the config entry as its path:]],
          table_block(report_labels, ctx.width),
          [[
The count line above them tallies every mutant, including the ones that leave
the score:]],
          table_block(count_labels, ctx.width),
          [[
`--strict` gates on the two undetected statuses. Everything else that fails a
run — a stale baseline entry, an exclude entry covering nothing — fails it on
its own, with or without the gate.]],
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

`ntf CMD --help` prints the options of any other command. Hooks, coverage and
mutation testing are documented in [doc/ntf.txt](doc/ntf.txt).

## Writing specs

```lua
%s```
]]):format(plugin_name, setup, usage, example)

  util.write("README.md", content)
end
gen_readme()

--- @type table<string, true> every token the command tree parses as a flag
local known_flags = {}
--- @param command any an NtfCommand, whose class this tree is checked apart from
local function collect_flags(command)
  for _, flag in ipairs(command.flags or {}) do
    known_flags[flag.name] = true
    for _, alias in ipairs(flag.aliases or {}) do
      known_flags[alias] = true
    end
  end
  for _, sub in ipairs(command.subcommands or {}) do
    collect_flags(sub)
  end
end
collect_flags(args.root)

-- WHY: the generated documents no longer show every command's usage, so this is
-- what says a flag they name in prose is still one the tree takes.
-- NOT: dumping the usage of every command, which the documents are shorter for.
for _, path in ipairs({ ("./doc/%s.txt"):format(plugin_name), "./README.md" }) do
  for token in util.read_all(path):gmatch("%-%-[%w-]+") do
    if not known_flags[token] then
      error(("%s names a flag no command takes: %s"):format(path, token))
    end
  end
end

-- WHY: a `>` on the line right after a list item is read as more of that item,
-- so the block is shown with its markers instead of as code, which only the
-- help parser can say - the text alone looks like every other block.
-- NOT: reading the rendered help, which is where this was first noticed.
local help_path = ("./doc/%s.txt"):format(plugin_name)
local help_text = util.read_all(help_path)
--- @type table<integer, true> the row each code block the help parser sees opens on
local code_block_rows = {}
local help_root = assert(vim.treesitter.get_string_parser(help_text, "vimdoc"):parse())[1]:root()
for _, node in vim.treesitter.query.parse("vimdoc", "(codeblock) @block"):iter_captures(help_root, help_text) do
  code_block_rows[(node:range()) + 1] = true
end
for row, line in ipairs(vim.split(help_text, "\n")) do
  if vim.startswith(line, ">") and not code_block_rows[row] then
    error(("%s:%d opens a code block the help parser does not see: %s"):format(help_path, row, line))
  end
end
