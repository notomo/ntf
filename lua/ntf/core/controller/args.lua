local M = {}

--- @type string[] the mutant statuses `--strict` can gate on; the bare flag selects all of them
local STRICT_CATEGORIES = { "survived", "no_coverage" }

--- @class NtfOptions
--- @field command string the resolved command: run, list, mutation.run, mutation.list, mutation.baseline.verify or mutation.baseline.add
--- @field paths string[] spec files or directories
--- @field timeout integer default per-worker timeout in ms (0 disables)
--- @field filter string? Lua pattern; keep only matching leaves
--- @field jobs integer? max parallel workers
--- @field test_hook string? Lua module returning optional setup/teardown, run once per test around its worker's spec
--- @field global_hook string? Lua module returning optional setup/teardown, run once in the launcher around the whole run
--- @field exclude_code string[] files or directories to leave out of the code under test
--- @field exclude_spec string[] spec files or directories to skip during discovery
--- @field coverage boolean measure line coverage of the code under test
--- @field coverage_file string stats output path (luacov.stats.out format)
--- @field mutation_target string? restrict the mutated files to this file or directory
--- @field mutation_strict table<string, true>? mutant statuses that fail the run (survived/no_coverage); nil disables the gate
--- @field mutation_config string? mutation policy file (JSON): the known-equivalent mutants and the unmutated paths
--- @field mutation_verify_baseline boolean run the baseline entries and fail any that a test can kill
--- @field mutation_verify_baseline_only boolean leave every mutant outside the baseline unrun
--- @field mutation_results string mutation results output path (JSON)
--- @field mutation_mutant { path: string, row: integer, col: integer, operator: string }? the mutant a baseline entry is written for
--- @field mutation_replacement string? what the mutant puts in place of the original, naming one of several mutants a position holds
--- @field mutation_rationale string? why no test can detect the mutant the entry is written for
--- @field mutation_invariant_spec string? full name of the test that fails once that rationale stops holding
--- @field help boolean show usage and exit

--- @class NtfFlag
--- @field name string the token the flag is parsed and documented under
--- @field aliases string[]? further tokens selecting the same flag
--- @field value string? placeholder for the value it takes; nil for a flag that takes none
--- @field optional boolean? the value may be left out
--- @field description string the line shown in usage
--- @field set fun(opts: NtfOptions, value: string?): string? applies the flag, returning an error message for a value it rejects

--- @class NtfCommand
--- @field name string the token the command is parsed and documented under
--- @field description string? the line the command is listed under; the root is never listed, so it has none
--- @field id string? the value the command sets on NtfOptions.command; leaf commands only
--- @field positional string? placeholder for the positional arguments it takes; nil for a command that takes none
--- @field defaults table<string, any>? option values the command itself implies, applied before its flags
--- @field flags NtfFlag[]? the flags it accepts, which is what makes a combination legal; leaf commands only
--- @field validate (fun(opts: NtfOptions): string?)? the check only this command can make
--- @field subcommands NtfCommand[]? the commands below it
--- @field default string? the subcommand taken when the next token names none

--- @type NtfFlag
local timeout = {
  name = "--timeout",
  value = "MS",
  description = "kill a worker after MS milliseconds (default: 60000; 0 disables)",
  set = function(opts, value)
    local ms = tonumber(value)
    if ms == nil or ms < 0 then
      return "invalid --timeout value (expected milliseconds >= 0)"
    end
    opts.timeout = ms
  end,
}

--- @type NtfFlag
local filter = {
  name = "--filter",
  value = "PATTERN",
  description = "run only tests whose full name matches the Lua pattern",
  set = function(opts, value)
    opts.filter = value
  end,
}

--- @type NtfFlag
local jobs = {
  name = "--jobs",
  value = "N",
  description = "max parallel nvim workers (default: cpu count)",
  set = function(opts, value)
    opts.jobs = tonumber(value)
  end,
}

--- @type NtfFlag
local test_hook = {
  name = "--test-hook",
  value = "FILE",
  description = "run a Lua module providing setup/teardown around each test, in its worker",
  set = function(opts, value)
    opts.test_hook = value
  end,
}

--- @type NtfFlag
local global_hook = {
  name = "--global-hook",
  value = "FILE",
  description = "run a Lua module providing setup/teardown once around the whole run, in the launcher process",
  set = function(opts, value)
    opts.global_hook = value
  end,
}

--- @type NtfFlag
local exclude_code = {
  name = "--exclude-code",
  value = "PATH",
  description = "leave a file or directory out of the code that is measured and mutated (repeatable)",
  set = function(opts, value)
    table.insert(opts.exclude_code, value)
  end,
}

--- @type NtfFlag
local exclude_spec = {
  name = "--exclude-spec",
  value = "PATH",
  description = "skip a spec file or directory when discovering tests (repeatable)",
  set = function(opts, value)
    table.insert(opts.exclude_spec, value)
  end,
}

--- @type NtfFlag
local coverage = {
  name = "--coverage",
  value = "FILE",
  optional = true,
  description = "measure line coverage; write luacov.stats.out (or FILE) and print a summary",
  set = function(opts, value)
    opts.coverage = true
    if value ~= nil then
      opts.coverage_file = value
    end
  end,
}

--- @type NtfFlag
local target = {
  name = "--target",
  value = "PATH",
  description = "restrict the mutated files to this file or directory",
  set = function(opts, value)
    opts.mutation_target = value
  end,
}

--- @type NtfFlag
local strict = {
  name = "--strict",
  value = "LIST",
  optional = true,
  description = "exit non-zero when any mutant is survived or no-coverage (LIST restricts the gate to a comma-separated subset)",
  set = function(opts, value)
    opts.mutation_strict = {}
    if value == nil then
      for _, status in ipairs(STRICT_CATEGORIES) do
        opts.mutation_strict[status] = true
      end
      return
    end
    for status in value:gmatch("[^,]+") do
      if not vim.tbl_contains(STRICT_CATEGORIES, status) then
        return "invalid --strict category: " .. status .. " (expected " .. table.concat(STRICT_CATEGORIES, ", ") .. ")"
      end
      opts.mutation_strict[status] = true
    end
  end,
}

--- @param description string what FILE is to the command taking it
--- @return NtfFlag
local function config_flag(description)
  return {
    name = "--config",
    value = "FILE",
    description = description,
    set = function(opts, value)
      opts.mutation_config = value
    end,
  }
end

--- @type NtfFlag
local config = config_flag(
  "take the mutation policy from FILE: its required operators say which operators run at all, its baseline of known-equivalent mutants leaves the score, its exclude paths stay unmutated; exit non-zero when an entry matches nothing"
)

--- @type NtfFlag
local written_config = config_flag("the mutation policy file to write the entry into, under its baseline")

--- @type NtfFlag
local verify_baseline = {
  name = "--verify-baseline",
  description = "run the --config baseline entries instead of trusting them, in the same pass that scores every other mutant; exit non-zero when a test kills one",
  set = function(opts)
    opts.mutation_verify_baseline = true
  end,
}

--- @type NtfFlag
local results = {
  name = "--results",
  value = "FILE",
  description = "mutation results output path (default: ntf-mutation.json)",
  set = function(opts, value)
    --- @cast value string
    opts.mutation_results = value
  end,
}

--- @type NtfFlag
local mutant = {
  name = "--mutant",
  value = "PATH:ROW:COL:OPERATOR",
  description = "the mutant to write a baseline entry for, spelled as a report prints it",
  set = function(opts, value)
    --- @cast value string
    local path, row, col, operator = value:match("^(.+):(%d+):(%d+):([%w-]+)$")
    if not path then
      return "invalid --mutant value (expected PATH:ROW:COL:OPERATOR)"
    end
    opts.mutation_mutant = {
      path = path,
      row = assert(tonumber(row)),
      col = assert(tonumber(col)),
      operator = operator,
    }
  end,
}

--- @type NtfFlag
local replacement = {
  name = "--replacement",
  value = "TEXT",
  description = "what the mutant puts in place of the original, needed only when its position holds more than one of the operator's mutants",
  set = function(opts, value)
    opts.mutation_replacement = value
  end,
}

--- @type NtfFlag
local rationale = {
  name = "--rationale",
  value = "TEXT",
  description = "why no test can detect the mutant, which is what a later judgement starts from",
  set = function(opts, value)
    opts.mutation_rationale = value
  end,
}

--- @type NtfFlag
local invariant_spec = {
  name = "--invariant-spec",
  value = "NAME",
  description = "full name of the test that fails once the rationale stops holding",
  set = function(opts, value)
    opts.mutation_invariant_spec = value
  end,
}

--- @type NtfFlag
local help = {
  name = "--help",
  aliases = { "-h" },
  description = "show this help",
  set = function(opts)
    opts.help = true
  end,
}

--- @type NtfFlag[] taken by every command, since every command discovers the specs it works from
local discovery_flags = { filter, global_hook, exclude_spec }

--- @type NtfFlag[] taken by every command that starts workers
local worker_flags = { timeout, jobs, test_hook }

--- @type NtfFlag[] taken by every mutation command that enumerates the mutants of the code under test
local mutation_flags = { exclude_code, target, config }

--- @type string what the commands whose positional arguments are spec paths spell them as
local SPEC_PATHS = "spec-file-or-dir..."

--- @param ... NtfFlag[]
--- @return NtfFlag[] # the given groups in order, followed by --help, which every command takes
local function command_flags(...)
  local all = {}
  for _, group in ipairs({ ... }) do
    vim.list_extend(all, group)
  end
  table.insert(all, help)
  return all
end

--- @type NtfCommand
local run_command = {
  name = "run",
  description = "run the tests and report the results",
  id = "run",
  positional = SPEC_PATHS,
  flags = command_flags(discovery_flags, worker_flags, { coverage, exclude_code }),
  validate = function(opts)
    if #opts.exclude_code > 0 and not opts.coverage then
      return "--exclude-code requires --coverage"
    end
  end,
}

--- @type NtfCommand
local list_command = {
  name = "list",
  description = "list the tests without running them",
  id = "list",
  positional = SPEC_PATHS,
  flags = command_flags(discovery_flags),
}

--- @type NtfCommand
local mutation_run_command = {
  name = "run",
  description = "mutate the covered code once the tests pass and score the mutants",
  id = "mutation.run",
  positional = SPEC_PATHS,
  flags = command_flags(discovery_flags, worker_flags, mutation_flags, { strict, verify_baseline, results }),
  validate = function(opts)
    if opts.mutation_verify_baseline and not opts.mutation_config then
      return "--verify-baseline requires --config"
    end
  end,
}

--- @type NtfCommand
local mutation_list_command = {
  name = "list",
  description = "list the mutants with coverage, without scoring them",
  id = "mutation.list",
  positional = SPEC_PATHS,
  flags = command_flags(discovery_flags, worker_flags, mutation_flags),
}

--- @type NtfCommand
local mutation_baseline_verify_command = {
  name = "verify",
  description = "run the baseline entries alone and fail any that a test can kill",
  id = "mutation.baseline.verify",
  positional = SPEC_PATHS,
  defaults = { mutation_verify_baseline = true, mutation_verify_baseline_only = true },
  flags = command_flags(discovery_flags, worker_flags, mutation_flags),
  validate = function(opts)
    if not opts.mutation_config then
      return "baseline verify requires --config, which is where the baseline entries live"
    end
  end,
}

--- @type NtfCommand
local mutation_baseline_add_command = {
  name = "add",
  description = "write the entry for one mutant into the baseline, leaving the tests unrun",
  id = "mutation.baseline.add",
  flags = command_flags({ written_config, mutant, replacement, rationale, invariant_spec }),
  validate = function(opts)
    if not opts.mutation_config then
      return "baseline add requires --config, which is the file the entry is written into"
    end
    if not opts.mutation_mutant then
      return "baseline add requires --mutant=PATH:ROW:COL:OPERATOR, which names the mutant the entry answers for"
    end
    if not opts.mutation_rationale then
      return "baseline add requires --rationale, which is what a later judgement starts from"
    end
  end,
}

--- @type NtfCommand
local mutation_baseline_command = {
  name = "baseline",
  description = "work on the --config baseline: verify its entries, or write one",
  default = "verify",
  subcommands = { mutation_baseline_verify_command, mutation_baseline_add_command },
}

--- @type NtfCommand
local mutation_command = {
  name = "mutation",
  description = "mutation-test the covered code",
  default = "run",
  subcommands = { mutation_run_command, mutation_list_command, mutation_baseline_command },
}

--- @type NtfCommand the command tree: a flag exists only under the commands that can act on it
M.root = {
  name = "ntf",
  default = "run",
  subcommands = { run_command, list_command, mutation_command },
}

--- @param command NtfCommand
--- @param name string
--- @return NtfCommand?
local function subcommand(command, name)
  for _, sub in ipairs(command.subcommands or {}) do
    if sub.name == name then
      return sub
    end
  end
end

--- @param argv string[] only its leading tokens name a command, so a path is never taken for one
--- @return NtfCommand[] chain, string[] rest # the commands from the root down to the leaf, and what is left to parse as flags and paths
function M.resolve(argv)
  local chain = { M.root }
  local command = M.root
  local i = 1
  while command.subcommands do
    local named = subcommand(command, argv[i] or "")
    if named then
      i = i + 1
    else
      named = assert(subcommand(command, command.default))
    end
    command = named
    table.insert(chain, command)
  end
  return chain, vim.list_slice(argv, i)
end

--- @type table<string, NtfCommand[]> leaf command id to its chain from the root
local chains = {}
--- @param chain NtfCommand[]
local function index_chains(chain)
  local command = chain[#chain]
  if not command.subcommands then
    chains[command.id] = chain
    return
  end
  for _, sub in ipairs(command.subcommands) do
    index_chains(vim.list_extend(vim.list_extend({}, chain), { sub }))
  end
end
index_chains({ M.root })

--- @param flag NtfFlag
--- @return string # the flag as usage spells it, e.g. "--coverage[=FILE]"
function M.flag_label(flag)
  local tokens = vim.list_extend({}, flag.aliases or {})
  table.insert(tokens, flag.name)
  local label = table.concat(tokens, ", ")
  if flag.value == nil then
    return label
  end
  if flag.optional then
    return label .. "[=" .. flag.value .. "]"
  end
  return label .. "=" .. flag.value
end

--- @param command NtfCommand
--- @param parent NtfCommand
--- @return string # the command as usage spells it, e.g. "run (default)"
function M.command_label(command, parent)
  if parent.default == command.name then
    return command.name .. " (default)"
  end
  return command.name
end

--- @param entries { label: string, description: string }[]
--- @return string[]
local function aligned(entries)
  local width = 0
  for _, entry in ipairs(entries) do
    width = math.max(width, #entry.label)
  end
  return vim
    .iter(entries)
    :map(function(entry)
      return ("  %-" .. (width + 2) .. "s%s"):format(entry.label, entry.description)
    end)
    :totable()
end

--- @param chain NtfCommand[]
--- @return string
local function chain_usage(chain)
  local command = chain[#chain]
  local parent = chain[#chain - 1]

  local names = {}
  for i = 2, #chain do
    local name = chain[i].name
    if chain[i - 1].default == name then
      name = "[" .. name .. "]"
    end
    table.insert(names, name)
  end

  local lines = {
    ("Usage: ntf %s [options]%s"):format(
      table.concat(names, " "),
      command.positional and (" [" .. command.positional .. "]") or ""
    ),
    "",
  }
  if parent.default == command.name then
    table.insert(lines, "Commands:")
    vim.list_extend(
      lines,
      aligned(vim
        .iter(parent.subcommands)
        :map(function(sub)
          return { label = M.command_label(sub, parent), description = sub.description }
        end)
        :totable())
    )
  else
    table.insert(lines, command.description)
  end

  table.insert(lines, "")
  table.insert(lines, "Options:")
  vim.list_extend(
    lines,
    aligned(vim
      .iter(command.flags)
      :map(function(flag)
        return { label = M.flag_label(flag), description = flag.description }
      end)
      :totable())
  )

  if command.positional then
    table.insert(lines, "")
    table.insert(lines, "With no paths, the *_spec.lua files under ./spec are used.")
  end
  return table.concat(lines, "\n")
end

--- @param command_id string? leaf command id; the default command when omitted
--- @return string
function M.usage(command_id)
  return chain_usage(chains[command_id or run_command.id])
end

--- @param opts NtfOptions
--- @return string? # error message for an option value the command cannot act on
local function validate(opts)
  if opts.filter and not pcall(string.find, "", opts.filter) then
    return "invalid --filter pattern: " .. opts.filter
  end
  if opts.test_hook and vim.fn.filereadable(opts.test_hook) == 0 then
    return "--test-hook module not found: " .. opts.test_hook
  end
  if opts.global_hook and vim.fn.filereadable(opts.global_hook) == 0 then
    return "--global-hook module not found: " .. opts.global_hook
  end
  for _, path in ipairs(opts.exclude_code) do
    if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
      return "--exclude-code path not found: " .. path
    end
  end
  for _, path in ipairs(opts.exclude_spec) do
    if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
      return "--exclude-spec path not found: " .. path
    end
  end
  if
    opts.mutation_target
    and vim.fn.filereadable(opts.mutation_target) == 0
    and vim.fn.isdirectory(opts.mutation_target) == 0
  then
    return "--target path not found: " .. opts.mutation_target
  end
  if opts.mutation_config and vim.fn.filereadable(opts.mutation_config) == 0 then
    return "--config file not found: " .. opts.mutation_config
  end
  if opts.mutation_mutant then
    if not require("ntf.core.mutation.operators").by_name[opts.mutation_mutant.operator] then
      return "--mutant names an operator no run produces: " .. opts.mutation_mutant.operator
    end
    if vim.fn.filereadable(opts.mutation_mutant.path) == 0 then
      return "--mutant file not found: " .. opts.mutation_mutant.path
    end
  end
end

--- @param argv string[]
--- @return NtfOptions|string # parsed options table, or an error message string
function M.parse(argv)
  local chain, rest = M.resolve(argv)
  local command = chain[#chain]

  local opts = {
    command = command.id,
    paths = {},
    timeout = 60000,
    filter = nil,
    jobs = nil,
    test_hook = nil,
    global_hook = nil,
    exclude_code = {},
    exclude_spec = {},
    coverage = false,
    coverage_file = "luacov.stats.out",
    mutation_target = nil,
    mutation_strict = nil,
    mutation_config = nil,
    mutation_verify_baseline = false,
    mutation_verify_baseline_only = false,
    mutation_results = "ntf-mutation.json",
    mutation_mutant = nil,
    mutation_replacement = nil,
    mutation_rationale = nil,
    mutation_invariant_spec = nil,
    help = false,
  }
  for key, value in pairs(command.defaults or {}) do
    opts[key] = value
  end

  local by_token = {}
  for _, flag in ipairs(command.flags) do
    by_token[flag.name] = flag
    for _, alias in ipairs(flag.aliases or {}) do
      by_token[alias] = flag
    end
  end

  local i = 1
  while i <= #rest do
    local current = rest[i]
    local token, inline = current:match("^(%-%-[%w-]+)=(.*)$")
    token = token or current
    --- @type NtfFlag?
    local flag = by_token[token]
    if flag and flag.value == nil and inline ~= nil then
      flag = nil
    end
    if flag then
      local value = inline
      if flag.value ~= nil and not flag.optional and value == nil then
        i = i + 1
        value = rest[i]
        if value == nil then
          return "missing value for " .. token .. "\n\n" .. chain_usage(chain)
        end
      end
      if flag.optional and value == "" then
        value = nil
      end
      local err = flag.set(opts, value)
      if err then
        return err
      end
    elseif current:sub(1, 1) == "-" then
      return "unknown option: " .. current .. "\n\n" .. chain_usage(chain)
    elseif not command.positional then
      return "unexpected argument: " .. current .. "\n\n" .. chain_usage(chain)
    else
      table.insert(opts.paths, current)
    end
    i = i + 1
  end

  if opts.help then
    return opts
  end
  if command.positional and #opts.paths == 0 then
    if vim.fn.isdirectory("spec") == 1 then
      opts.paths = { "spec" }
    else
      return "no spec paths given\n\n" .. chain_usage(chain)
    end
  end

  local err = validate(opts)
  if err then
    return err
  end
  if command.validate then
    return command.validate(opts) or opts
  end
  return opts
end

return M
