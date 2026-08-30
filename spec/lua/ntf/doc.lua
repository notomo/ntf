vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("genvdoc.util")
local args = require("ntf.core.controller.args")
local builder = require("ntf.assert.builder")
local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")
local report = require("ntf.core.mutation.report")
local config = require("ntf.core.mutation.config")
local plugin_name = vim.env.PLUGIN_NAME

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

local process_hook_path = doc_dir .. "/process_hook.lua"
run_ntf({ "--process-hook=" .. process_hook_path, example_spec })
local process_hook_command = "ntf --process-hook=./" .. vim.fs.basename(process_hook_path)

local global_hook_path = doc_dir .. "/global_hook.lua"
run_ntf({ "--global-hook=" .. global_hook_path, example_spec })
local global_hook_command = "ntf --global-hook=./" .. vim.fs.basename(global_hook_path)

local dependency_hook_path = doc_dir .. "/dependency_hook.lua"
local dependency_dir = vim.fn.tempname()
vim.fn.mkdir(vim.fs.joinpath(dependency_dir, "deps/dependency/lua"), "p")
vim.fn.mkdir(vim.fs.joinpath(dependency_dir, "deps/dependency/plugin"), "p")
vim.fn.mkdir(vim.fs.joinpath(dependency_dir, "spec"), "p")
vim.fn.writefile({
  "return { value = 1 }",
}, vim.fs.joinpath(dependency_dir, "deps/dependency/lua/dependency.lua"))
vim.fn.writefile({
  "vim.g.dependency_plugin_loaded = true",
}, vim.fs.joinpath(dependency_dir, "deps/dependency/plugin/dependency.lua"))
vim.fn.writefile({
  'local ntf = require("ntf")',
  'local dependency = require("dependency")',
  'ntf.it("reaches the dependency the hook put on the runtimepath", function()',
  "  ntf.assert.equal(1, dependency.value)",
  "  ntf.assert.is_true(vim.g.dependency_plugin_loaded)",
  "end)",
}, vim.fs.joinpath(dependency_dir, "spec/dependency_spec.lua"))
run_ntf({
  "--process-hook=" .. vim.fn.fnamemodify(dependency_hook_path, ":p"),
  "spec",
}, { cwd = dependency_dir })
local dependency_hook_command = "ntf --process-hook=./" .. vim.fs.basename(dependency_hook_path)

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

-- WHY: what these commands do is asserted, output and all, by the end-to-end
-- tests of init_spec.lua, which run the same flags through bin/ntf.
-- NOT: running each of them here too, which spends a CLI run — several of them
-- whole mutation runs — to learn only that it exits 0.
local coverage_command = "ntf --coverage"
local coverage_stats_file_command = "ntf --coverage=luacov.stats.out"
local exclude_code_command = "ntf --coverage --exclude-code=lua/vendor --exclude-code=lua/mymod/test"
local list_command = "ntf list"
local mutation_command = "ntf mutation"
local mutation_strict_command = "ntf mutation --strict"
local mutation_list_command = "ntf mutation list"

local mutation_config_path = doc_dir .. "/mutation_config.json"
local mutation_operators_path = doc_dir .. "/mutation_operators.json"
local project_config_path = vim.fs.joinpath(project_dir, "spec/mutation.json")

vim.fn.writefile(vim.fn.readfile(mutation_operators_path), vim.fs.joinpath(project_dir, "spec/operators.json"))
run_ntf({
  "mutation",
  "--target=lua/mymod.lua",
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
  "--mutant=lua/mymod.lua:3:14:perturb-number",
  "--rationale=" .. rationale,
  "--invariant-spec=" .. invariant_spec,
}, { cwd = project_dir })
local mutation_baseline_add_command = table.concat({
  "ntf mutation baseline add --config=spec/mutation.json \\",
  "  --mutant=lua/mymod.lua:3:14:perturb-number \\",
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
  "--config=spec/mutation.json",
  "--strict",
  "spec",
}, { cwd = project_dir })
local mutation_config_command = "ntf mutation --config=spec/mutation.json"

local mutation_verify_baseline_command = "ntf mutation baseline verify --config=spec/mutation.json"
local mutation_verify_baseline_with_score_command =
  "ntf mutation --config=spec/mutation.json --strict --verify-baseline"

run_ntf({
  "mutation",
  "--config=spec/mutation.json",
  "spec",
}, { cwd = project_dir })

for _, command in ipairs({
  test_hook_command,
  process_hook_command,
  global_hook_command,
  dependency_hook_command,
  debug_command,
  coverage_command,
  coverage_stats_file_command,
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

--- @class NtfDocEntry
--- @field label string the name the document lists, as the implementation spells it
--- @field description string what the document says it is
--- @field note string? what its own section adds, where it has one
--- @field absent boolean? the example carries no such key, it being written only where it is needed

--- @param entries NtfDocEntry[]
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

--- @param names string[]
--- @return string[] # a sorted copy, for names no order is meant to be read into
local sorted = function(names)
  local copy = vim.list_extend({}, names)
  table.sort(copy)
  return copy
end

--- @class NtfDocEnumeration
--- @field what string what the document calls the names
--- @field entries NtfDocEntry[] the names the document spells, in the order it lists them
--- @field in_use string[] the names the implementation works from
--- @field keys_of table? a documented example whose keys the names have to answer for, every name but an `absent` one being carried
--- @field unordered boolean? for names no order is meant to be read into

-- WHY: an implementation that gains a name the document has never heard of is
-- what a check against the document's own example cannot see, so the names come
-- from the tables the code itself works from.
-- NOT: listing the names twice and comparing the document to a copy of itself.
--- @param opts NtfDocEnumeration
--- @return NtfDocEntry[] # the entries, once they are the names in use
local enumeration = function(opts)
  local names = vim.tbl_map(function(entry)
    return entry.label
  end, opts.entries)

  local spelled, in_use = names, opts.in_use
  if opts.unordered then
    spelled, in_use = sorted(spelled), sorted(in_use)
  end
  if not vim.deep_equal(spelled, in_use) then
    error(("the %s the document spells are not the ones in use: %s"):format(opts.what, vim.inspect(opts.in_use)))
  end

  if opts.keys_of then
    local expected = sorted(vim.tbl_map(
      function(entry)
        return entry.label
      end,
      vim.tbl_filter(function(entry)
        return not entry.absent
      end, opts.entries)
    ))
    local carried = sorted(vim.tbl_keys(opts.keys_of))
    if not vim.deep_equal(expected, carried) then
      error(("the %s the example file carries are not the documented ones: %s"):format(opts.what, vim.inspect(carried)))
    end
  end

  return opts.entries
end

--- @type NtfDocEntry[] what a test has to do to detect each operator's mutant, and what its own section adds, in the order the document lists them
local operator_descriptions = enumeration({
  what = "operator names",
  in_use = vim.tbl_map(function(operator)
    return operator.name
  end, operators.operators),
  entries = {
    { label = "swap-relational", description = "a test has to exercise the boundary value the two disagree on" },
    { label = "swap-logical", description = "a test has to reach operands the two connectives disagree on" },
    {
      label = "swap-arithmetic",
      description = "a test has to exercise a right operand the two disagree on",
      note = [[
The bitwise operators have no site of this operator, and neither does
`//`, which the runtime a mutant is loaded in cannot compile.]],
    },
    {
      label = "swap-boolean",
      description = "a test has to depend on the value, not merely execute the line",
      note = [[
A condition spelled as a bare `true` or `false` is a site of this operator
rather than of |ntf-force-branch|, so it is changed once instead of forced
to each outcome it already names.]],
    },
    { label = "drop-not", description = "a test has to reach the branch the negation decides" },
    { label = "drop-negation", description = "a test has to exercise a nonzero operand and depend on its sign" },
    {
      label = "perturb-number",
      description = "a test has to depend on the exact value, not on its being non-zero",
      note = "A hexadecimal literal is shifted into decimal, so `0x10` becomes `17`.",
    },
    {
      label = "perturb-length",
      description = "a test has to depend on the exact count, not on its being non-zero",
      note = [[
The shifted count is parenthesized, so whatever the expression sits under
still takes all of it.]],
    },
    {
      label = "force-branch",
      description = "each outcome needs a test that depends on which side ran",
      note = [[
Only the condition is rewritten, so each mutant keeps the body it decides
over.]],
    },
    {
      label = "force-loop",
      description = "a test has to depend on the body running, which a repeat still does once",
      note = [[
A `while` is pinned to false and a `repeat` to true — the outcome that
leaves the loop, since the other spins forever to prove nothing a coverage
hit does not already. A `for` is rewritten to the clause of its own kind
that iterates none, so its body never runs.]],
    },
    {
      label = "drop-call",
      description = "a test has to observe what the call does, not merely reach its line",
      note = [[
Only a call standing as a statement of its own: deleting one whose value
is used would take the expression around it too.]],
    },
    {
      label = "drop-assignment",
      description = "a test has to observe what the assignment stores, not merely reach it",
      note = [[
A `local` declaration is left alone, since deleting it would rewrite the
scope every later mention of the name is read through, and not the store.]],
    },
    {
      label = "drop-return-value",
      description = "a test has to depend on what the function answers, not merely reach it",
      note = [[
Only a return that answers for a function: the one a chunk answers with is
the module itself. A return of a single literal is left to that literal's
own operator, which already owns the change.]],
    },
  },
})
local description_by_operator = {}
for _, entry in ipairs(operator_descriptions) do
  description_by_operator[entry.label] = entry
end

--- @param ctx { width: integer } the document width a line has to fit in
--- @return string # every operator under a tag of its own, with the change its example gets and what detects it
local operator_sections = function(ctx)
  local sections = {}
  for _, operator in ipairs(operators.operators) do
    local sites = operators.enumerate(operator.example)
    local changes = {}
    for _, site in ipairs(sites) do
      local mutated = assert(splice.apply(operator.example, site), "example does not match its site")
      table.insert(changes, ("%s -> %s"):format(operator.example, mutated))
    end

    local entry = description_by_operator[operator.name]
    local prose = { entry.description }
    if entry.note then
      table.insert(prose, "")
      table.insert(prose, vim.trim(entry.note))
    end
    local body = util.indent(table.concat(prose, "\n"), 2)

    local section = util.help_tagged(ctx, operator.name, "ntf-" .. operator.name)
      .. util.help_code_block(table.concat(changes, "\n"))
      .. "\n"
      .. body
    for _, line in ipairs(vim.split(section, "\n", { plain = true })) do
      if #line > ctx.width then
        error(("too long for the document width: %s"):format(line))
      end
    end
    table.insert(sections, section)
  end
  return table.concat(sections, "\n\n")
end

local sections_by_key = {}
for _, section in ipairs(config.sections) do
  sections_by_key[section.key] = section
end

--- @type NtfDocEntry[] the config file's sections
local config_sections = enumeration({
  what = "config sections",
  in_use = vim.list_extend(
    { "version", "operators" },
    vim.tbl_map(function(section)
      return section.key
    end, config.sections)
  ),
  keys_of = documented,
  entries = {
    { label = "version", description = "the policy file format, currently 1 (required)" },
    { label = "operators", description = "which operators produce mutants at all (required)" },
    { label = "baseline", description = "the mutants judged impossible to kill" },
    { label = "exclude", description = "files whose mutants the run leaves out" },
    { label = "exclude_spec", description = "specs never picked as a mutant's trial" },
  },
})

--- @type NtfDocEntry[] what a baseline entry names its mutant by
local baseline_fields = enumeration({
  what = "baseline entry fields",
  in_use = sections_by_key.baseline.fields,
  keys_of = documented.baseline[1],
  entries = {
    { label = "path", description = "the mutated file, relative to the working directory" },
    {
      label = "row",
      description = "the 1-based line, only where the content names two mutants",
      absent = true,
    },
    { label = "col", description = "the 1-based column the mutant starts at" },
    { label = "operator", description = "the change, named as the report names it" },
    { label = "original", description = "what the mutant replaces" },
    { label = "replacement", description = "what it puts there" },
    { label = "line", description = "the text of the line, matched instead of a row" },
    { label = "rationale", description = "why no test can detect it (required)" },
    { label = "invariant_spec", description = "full name of the test the rationale rests on" },
    {
      label = "uncovered",
      description = "true where no test reaches it, so nothing re-runs it",
      absent = true,
    },
  },
})

--- @type NtfDocEntry[] what an exclude entry answers for
local exclude_fields = enumeration({
  what = "exclude entry fields",
  in_use = sections_by_key.exclude.fields,
  keys_of = documented.exclude[1],
  entries = {
    { label = "path", description = "the file the entry answers for" },
    { label = "operators", description = '"all", or the operator names to leave out (required)' },
    { label = "rationale", description = "why its mutants are left out (required)" },
  },
})

--- @type NtfDocEntry[] what an exclude_spec entry answers for
local exclude_spec_fields = enumeration({
  what = "exclude_spec entry fields",
  in_use = sections_by_key.exclude_spec.fields,
  keys_of = documented.exclude_spec[1],
  entries = {
    { label = "path", description = "the spec the entry answers for" },
    { label = "rationale", description = "why it is never a trial (required)" },
  },
})

local listed_in_use = vim.tbl_values(report.entry_labels)
for _, listed in pairs(report.listed) do
  table.insert(listed_in_use, listed.label)
end

--- @type NtfDocEntry[] the lines a mutation run lists a judgement under
local report_labels = enumeration({
  what = "report labels",
  in_use = listed_in_use,
  unordered = true,
  entries = {
    { label = "TIMEOUT", description = "a hung test detected it, which a busy machine can fake" },
    { label = "SURVIVED", description = "no test noticed the change" },
    { label = "NO COVERAGE", description = "no test reaches the line, so it was never run" },
    { label = "NOT APPLIED", description = "the file was not `require`d, so nothing changed" },
    { label = "BASELINE KILLABLE", description = "a baseline entry a test kills, named with the test" },
    { label = "LOST BASELINE", description = "a baseline entry whose `line` is no longer there" },
    { label = "AMBIGUOUS BASELINE", description = "its content names two mutants and it carries no `row`" },
    { label = "UNPINNED BASELINE", description = "its `invariant_spec` names no test that passed" },
    { label = "UNCOVERED BASELINE", description = "no test reaches it and it carries no `uncovered`" },
    { label = "COVERED BASELINE", description = "it carries `uncovered`, but a test reaches it" },
    { label = "UNUSED EXCLUDE", description = "an `exclude` entry covering no measurable file" },
    { label = "UNUSED EXCLUDE SPEC", description = "an `exclude_spec` entry covering no spec file" },
  },
})

--- @type NtfDocEntry[] the statuses the count line tallies
local count_labels = enumeration({
  what = "count line labels",
  in_use = vim.tbl_map(function(entry)
    return entry.label
  end, report.count_labels),
  entries = {
    { label = "killed", description = "detected: a test failed on the mutant" },
    { label = "timeout", description = "detected: a test hung and its worker was killed" },
    { label = "survived", description = "undetected: the tests stayed green" },
    { label = "no coverage", description = "undetected: no test reached the line" },
    { label = "not applied", description = "the mutant never landed, so it says nothing" },
    { label = "equivalent", description = "a `baseline` entry, left out of the score" },
    { label = "excluded", description = "an `exclude` entry's operator, out of the score" },
    { label = "unadopted", description = "an operator `operators` does not take" },
    { label = "baseline killable", description = "a `baseline` entry a test killed" },
  },
})

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
- `bin/ntf` (and `bin/ntf.bat` on Windows) launches the `nvim` found on `$PATH`.
  Set `$NTF_NVIM` to a binary to run the launcher and its workers with that one
  instead. It has to be Neovim 0.12.0 or later.
- |ntf-HOOKS|, |ntf-COVERAGE| and |ntf-MUTATION-TESTING| cover the rest.]],
        }, "\n")
      end,
    },
    {
      name = "WRITING SPECS",
      body = function()
        return table.concat({
          util.help_code_block_from_file(example_path, { language = "lua" }),
          [[
A test's full name — the enclosing `describe` names and its own, joined by
spaces — has to be its own within the file. Two tests sharing one fails the
file, naming both declaration sites, rather than running either: nothing tells
them apart afterwards, not the report, not `--filter`, not the schedule the
next run is ordered from, and not the worker, which picks a test by its
position in the file. So a test built in a loop puts what varies into its name:
]],
          util.help_code_block(
            table.concat({
              "for _, n in ipairs({ 1, 2, 3 }) do",
              '  it("case " .. n, function()',
              "    assert.equal(n, subject(n))",
              "  end)",
              "end",
            }, "\n"),
            { language = "lua" }
          ),
          [[
A name is a single line, whatever the source spelled it over: a break in it, a
newline the case data carried in included, is written as the `\n` it is, and
every other character stands as the source wrote it. So a listing keeps one
line per test, and that written form is the name — what two tests may not
share, and what a `--filter` pattern, the schedule and an `invariant_spec` are
all matched against — so the name a report shows is the one to write back.

The tests are declared once to plan the run and once again in each worker, and
a worker is handed the position of the test it is to run. So the declarations
have to come out the same both times: a file that decides what to declare from
anything the two processes do not share — what another spec file left behind in
the launcher, what a hook set up in the worker, the order `pairs()` hands back
— gives that position to another test. A worker that finds a different tree
than the run was planned from says so and runs nothing, rather than running the
test that took the position.]],
        }, "\n")
      end,
    },
    {
      name = "HOOKS",
      body = function(ctx)
        return table.concat({
          [[
A hook module returns an optional `setup` and an optional `teardown`. Which
process runs them, and how often, is what the three flags differ in. A module
that returns anything else -- the function itself, rather than a table holding
it -- or that carries a key neither hook is read from, is rejected naming what
it returned, rather than loading as a hook that does nothing.]],
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
build a fixture once — while `--test-hook` remains the per-test bracket. What
it sets in its own process, the runtimepath included, no worker sees — that is
|ntf-hook-process|, which every process runs.]],
          util.help_code_block(global_hook_command, { language = "sh" }),
          [[
- An error while loading the module, or from its `setup`, aborts the run before
  any test starts.
- A `teardown` error is reported after the results, and fails the run without
  discarding them.]],
          "\n" .. util.help_tagged(ctx, "--process-hook=FILE", "ntf-hook-process"),
          [[
Run in every process ntf starts — the launcher and each worker alike — before
that process loads a spec, which makes it the one hook the two of them agree
on. It is for what a process has to be before it can read a spec at all: the
runtimepath a dependency plugin sits on, a `package.path` entry, a stub. It
takes a `setup` and nothing else — it says what a process is rather than what it
brackets, so a module carrying a `teardown` is rejected before any test runs,
naming the two flags a teardown does belong in.]],
          util.help_code_block_from_file(process_hook_path, { language = "lua" }),
          util.help_code_block(process_hook_command, { language = "sh" }),
          [[
- The launcher loads every spec file to discover the tests in it, so a module a
  spec requires at file scope has to reach the launcher as well as the workers.
  This is the only hook that reaches both.
- An error while loading the module, or from its `setup`, aborts the run before
  any test starts.]],
          "\n" .. util.help_tagged(ctx, "Loading dependency plugins", "ntf-hook-dependency"),
          [[
A worker is a clean `nvim`, started with none of your config or plugins, so its
runtimepath holds ntf and the plugin under test (the working directory) and
nothing else. A plugin your specs depend on is put there by `--process-hook`,
whose `setup` runs before a spec is loaded, in every process that loads one:]],
          util.help_code_block_from_file(dependency_hook_path, { language = "lua" }),
          util.help_code_block(dependency_hook_command, { language = "sh" }),
          [[
- `--test-hook` cannot do this: it runs only in a worker, so a spec that
  requires the dependency at file scope still fails to load in the launcher,
  which reads every spec file to discover its tests.
- `--global-hook` cannot do this either: it runs only in the launcher, whose
  runtimepath no worker inherits.
- The runtimepath alone only makes the dependency's `lua/` and other runtime
  files findable; startup is over, so its `plugin/` scripts are sourced only
  where the second line does it.]],
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
per-worker counts, prints a short summary, and writes the counts in the
`luacov.stats.out` format:]],
          util.help_code_block(coverage_command, { language = "sh" }),
          [[
The stats go to a cache file named for the working directory (under
`stdpath("cache")/ntf/coverage/`), so that every project you run ntf in keeps
its own instead of the runs overwriting one another, and
|ntf.coverage.decorate()| reads that same file back with no path to configure.
`--coverage=FILE` writes them where you name instead.

What it measures:

- every file under the working directory, except the test tree: any
  `*_spec.lua` file, and `./spec` when the project has one — the directory a run
  naming no path discovers from — so anything sitting alongside the specs there,
  cloned test dependencies say, is left out too. That is the whole of it: the
  paths you name pick which specs run, never which code is measured, so code
  that sits beside its own specs is measured like any other
- a measured file no test executed, which shows up at 0%
- but never a LuaCATS meta file, which by definition never runs

A run that measured no line at all fails rather than reporting a coverage of
`n/a` that reads like a clean gate.

Not everything under the working directory is code you hold your tests to —
vendored third-party files, your own test helpers, a test tree that is not
`./spec` and so is measured like the rest. `--exclude-code=PATH` leaves a file
or directory out of the code under test; repeat it for each one. The `mutation`
commands take it too, since they measure the same code:]],
          util.help_code_block(exclude_code_command, { language = "sh" }),
          [[
The built-in summary is intentionally simple (its line classification is a
heuristic). For an authoritative or HTML report, hand the stats to LuaCov —
which ntf does not depend on — by writing them where it looks:]],
          util.help_code_block(
            table.concat({
              "luarocks install luacov",
              coverage_stats_file_command,
              "luacov          # reads luacov.stats.out -> luacov.report.out",
            }, "\n"),
            { language = "sh" }
          ),
          [[
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
  to a cache file named for the working directory (under
  `stdpath("cache")/ntf/mutation/`, as `--coverage` files its stats), which
  |ntf.mutation.decorate()| reads back to set the survivors as diagnostics in a
  buffer with no path to configure — in a namespace of its own, so that
  `vim.diagnostic.jump()` and `setloclist()` can take the survivors alone.
  `--results=FILE` writes it where you name instead.
- A mutant is spliced in when the module is `require`d, so a file the specs
  load through `dofile`/`loadfile` keeps its original source and is reported
  NOT APPLIED — never as a survivor. It leaves the score instead of passing it,
  so a run that reached no code at all scores nothing rather than scoring well.

`--strict` turns the score into a gate, exiting non-zero when any mutant
survived, was left uncovered, or never landed. `--strict=survived` (or
`=no_coverage`, `=not_applied`) gates only that category, so the bar can be
raised in steps:]],
          util.help_code_block(mutation_strict_command, { language = "sh" }),
          [[
A run that enumerated no mutant at all fails whatever `--strict` was asked for,
since its categories count the mutants a run did enumerate: a `--target` naming
no file to mutate, or an `exclude` covering every one of them, otherwise reports
a score of `n/a` that reads like a clean gate.

To see what a run would cover before paying for it, `ntf mutation list` runs
the tests once and lists the mutants with the number of tests that reach each:]],
          util.help_code_block(mutation_list_command, { language = "sh" }),
          [[
A listing holds its `--config` to the same account a scoring run does, since
none of that judgement waits on a mutant being run: an entry of `baseline`,
`exclude` or `exclude_spec` that the code no longer holds is reported and fails
the listing, rather than being left for the run the listing was to be read
before.]],
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
value by one.

Each has a tag of its own, and is shown with the change its own example gets
and with what a test has to do to detect it.]],
          "\n" .. operator_sections(ctx),
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

Nothing outside those sections is read, so nothing outside them is kept: a key
none of them names — a misspelled `excludes`, say — is rejected before the
tests run, rather than being applied by nothing and then dropped the next time
`baseline add` writes the file. An entry is held to its own fields the same
way.

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
  copy rather than a translation. Its row and column are both counted from 1,
  the way an editor and an 'errorformat' count them.
- `--replacement` is only needed where a single position holds more than one of
  that operator's mutants — the forced branch, which has one per outcome. Such
  a position is answered with the replacements to choose from rather than
  guessed at.
- The file stays a plain document written in one shape, so editing it by hand
  remains first-class.

An entry names its mutant by content rather than by position, so it survives the
line moving. Where a file carries the same line twice — same text, same column,
same operator — the content names two mutants and cannot say which one the
rationale answers for, and the run fails as AMBIGUOUS BASELINE rather than
excusing both behind one reason. `row` is what separates them, and
`baseline add` writes it exactly where it is needed: an entry that carries one
goes LOST BASELINE as soon as its line moves, which is the churn a content key
spares every other entry.

An entry is otherwise only ever trusted, not checked: a mutant a new test would
now detect stays out of the score behind a mark that no longer holds.
`ntf mutation baseline verify` runs the listed mutants instead of trusting
them, reporting BASELINE KILLABLE with the test that did it and exiting
non-zero. It leaves every other mutant unrun, scoring nothing and writing no
results file, which is what you want right after editing the baseline:]],
          util.help_code_block(mutation_verify_baseline_command, { language = "sh" }),
          [[
Verify fails the same way when it re-ran none of the entries its config lists,
so a run scoped past all of them is answered rather than passing as `0/0`.

A kill has to repeat before it counts, so a test that fails for reasons of its
own does not condemn an entry. `--verify-baseline` asks the same question of a
scoring run, verifying the entries in the same pass that scores the rest, so a
gate that wants both answers pays for one run of the suite instead of two:]],
          util.help_code_block(mutation_verify_baseline_with_score_command, { language = "sh" }),
          [[
An entry is re-run by the tests that reach its mutant, so one no test reaches
has nothing to re-run and would otherwise pass by saying nothing at all. Such
an entry makes the second claim itself: `uncovered`, which
`ntf mutation baseline add --uncovered` writes, says no test runs the line —
a different statement from the rest of the baseline's "the tests cannot tell the
difference". Both halves are held to the suite, and both fail the run:
UNCOVERED BASELINE, once an entry without the mark is reached by no test, and
COVERED BASELINE, once an entry carrying it is reached by one, which leaves the
mark something to be verified by after all. Reaching the mutant with a spec is
still what a NO COVERAGE mutant asks for; the mark is for the line a spec
cannot reach. Only the whole suite can say that nothing reaches a mutant, so
UNCOVERED BASELINE is answered for only where the run takes every test the
project has, while a test that does reach one says so however few were
selected. Verify's own line counts the entries it stood behind apart from the
ones it re-ran.

Two report lines answer for an entry that has gone stale, and both fail the
run: LOST BASELINE, once the `line` it marks is no longer there, and UNPINNED
BASELINE, once no test named by `invariant_spec` passes. A rationale usually
rests on a fact from somewhere else — what the callers pass, what shape another
module hands over, what the runtime does with a value — and that fact can stop
holding without the marked line moving. Naming the test that pins it is what
makes renaming or deleting that test something to answer for, instead of
quietly unmooring the rationale. A run that takes part of the suite cannot tell
a name that is gone from one it never selected, so UNPINNED BASELINE is
answered for only where the run takes every test the project has.]],
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
a broader entry, has to be answered for. An `exclude_spec` entry outside the
spec paths the run was given is left alone, the run never having looked for the
file it names.]],
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
`--strict` gates on the three undetected statuses: survived, no coverage and
not applied. A run that scored no mutant at all says so — `Mutation: n/a (no
mutant scored)` — instead of reading as a run with nothing to do. Everything
else that fails a run — a stale baseline entry, an exclude entry covering
nothing — fails it on its own, with or without the gate.]],
        }, "\n")
      end,
    },
    {
      name = "HIGHLIGHT GROUPS",
      body = function(ctx)
        local files = {
          ("./lua/%s/coverage/highlight_group.lua"):format(plugin_name),
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

`bin/ntf` is the CLI (`bin/ntf.bat` on Windows). It runs the `nvim` found on
`$PATH`, or the one `$NTF_NVIM` names, which has to be Neovim 0.12.0 or later.
With ntf installed as a Neovim plugin, you can expose the command to
`:terminal` (and anything else Neovim spawns) by prepending its `bin` directory
to `$PATH`:

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
  local content = util.read_all(path)
  for token in content:gmatch("%-%-[%w-]+") do
    if not known_flags[token] then
      error(("%s names a flag no command takes: %s"):format(path, token))
    end
  end
  -- WHY: a modifier is prose inside a doc source, not a name list the
  -- enumeration check can compare, so this is what says `assert.X.y` names a
  -- modifier the DSL answers to.
  -- NOT: trusting review, which let the documents offer `assert.is_not` long
  -- after `no` was the only modifier.
  for modifier in content:gmatch("assert%.([%a_][%w_]*)%.") do
    if not builder.negations[modifier] then
      error(("%s names an assert modifier the DSL does not have: %s"):format(path, modifier))
    end
  end
end
