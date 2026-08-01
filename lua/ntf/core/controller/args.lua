local M = {}

--- @type string[] the mutant statuses `--mutation-strict` can gate on; the bare flag selects all of them
local STRICT_CATEGORIES = { "survived", "no_coverage" }

local DEFAULT_MATRIX_CAP = math.huge

--- @class NtfOptions
--- @field paths string[] spec files or directories
--- @field timeout integer default per-worker timeout in ms (0 disables)
--- @field filter string? Lua pattern; keep only matching leaves
--- @field list boolean list the tests instead of reporting a run
--- @field jobs integer? max parallel workers
--- @field test_hook string? Lua module returning optional setup/teardown, run once per test around its worker's spec
--- @field global_hook string? Lua module returning optional setup/teardown, run once in the launcher around the whole run
--- @field exclude_code string[] files or directories to leave out of the code under test
--- @field exclude_spec string[] spec files or directories to skip during discovery
--- @field coverage boolean measure line coverage of the code under test
--- @field coverage_file string stats output path (luacov.stats.out format)
--- @field mutation boolean mutation-test the covered code after a passing run
--- @field mutation_path string? restrict the mutated files to this file or directory
--- @field mutation_strict table<string, true>? mutant statuses that fail the run (survived/no_coverage); nil disables the gate
--- @field mutation_matrix number? record every killer of each mutant covered by at most this many tests (math.huge for all of them); nil records only the first
--- @field mutation_config string? mutation policy file (JSON): the known-equivalent mutants and the unmutated paths
--- @field mutation_verify_baseline boolean run the baseline entries and fail any that a test can kill
--- @field mutation_results string mutation results output path (JSON)
--- @field help boolean show usage and exit

--- @class NtfFlag
--- @field name string the token the flag is parsed and documented under
--- @field aliases string[]? further tokens selecting the same flag
--- @field value string? placeholder for the value it takes; nil for a flag that takes none
--- @field optional boolean? the value may be left out
--- @field description string the line shown in usage
--- @field set fun(opts: NtfOptions, value: string?): string? applies the flag, returning an error message for a value it rejects

--- @type NtfFlag[]
M.flags = {
  {
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
  },
  {
    name = "--filter",
    value = "PATTERN",
    description = "run only tests whose full name matches the Lua pattern",
    set = function(opts, value)
      opts.filter = value
    end,
  },
  {
    name = "--list",
    description = "list the tests without running them (with --mutation, run the tests and list the mutants with coverage)",
    set = function(opts)
      opts.list = true
    end,
  },
  {
    name = "--jobs",
    value = "N",
    description = "max parallel nvim workers (default: cpu count)",
    set = function(opts, value)
      opts.jobs = tonumber(value)
    end,
  },
  {
    name = "--test-hook",
    value = "FILE",
    description = "run a Lua module providing setup/teardown around each test, in its worker",
    set = function(opts, value)
      opts.test_hook = value
    end,
  },
  {
    name = "--global-hook",
    value = "FILE",
    description = "run a Lua module providing setup/teardown once around the whole run, in the launcher process",
    set = function(opts, value)
      opts.global_hook = value
    end,
  },
  {
    name = "--exclude-code",
    value = "PATH",
    description = "leave a file or directory out of the code --coverage measures and --mutation mutates (repeatable)",
    set = function(opts, value)
      table.insert(opts.exclude_code, value)
    end,
  },
  {
    name = "--exclude-spec",
    value = "PATH",
    description = "skip a spec file or directory when discovering tests (repeatable)",
    set = function(opts, value)
      table.insert(opts.exclude_spec, value)
    end,
  },
  {
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
  },
  {
    name = "--mutation",
    value = "PATH",
    optional = true,
    description = "mutation-test the covered code (only under PATH, if given) once the tests pass",
    set = function(opts, value)
      opts.mutation = true
      opts.mutation_path = value
    end,
  },
  {
    name = "--mutation-strict",
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
          return "invalid --mutation-strict category: "
            .. status
            .. " (expected "
            .. table.concat(STRICT_CATEGORIES, ", ")
            .. ")"
        end
        opts.mutation_strict[status] = true
      end
    end,
  },
  {
    name = "--mutation-matrix",
    value = "N",
    optional = true,
    description = "record every test that detects a mutant and report the tests that detect nothing on their own (N restricts it to the mutants covered by at most N tests)",
    set = function(opts, value)
      opts.mutation_matrix = DEFAULT_MATRIX_CAP
      if value == nil then
        return
      end
      local cap = tonumber(value)
      if not cap or cap < 1 then
        return "invalid --mutation-matrix value (expected a test count >= 1)"
      end
      opts.mutation_matrix = cap
    end,
  },
  {
    name = "--mutation-config",
    value = "FILE",
    description = "take the mutation policy from FILE: its baseline of known-equivalent mutants leaves the score, its exclude paths stay unmutated; exit non-zero when an entry matches nothing",
    set = function(opts, value)
      opts.mutation_config = value
    end,
  },
  {
    name = "--mutation-verify-baseline",
    description = "run the --mutation-config baseline entries alone instead of trusting them, scoring no other mutant and writing no results file; exit non-zero when a test kills one",
    set = function(opts)
      opts.mutation_verify_baseline = true
    end,
  },
  {
    name = "--mutation-results",
    value = "FILE",
    description = "mutation results output path (default: ntf-mutation.json)",
    set = function(opts, value)
      --- @cast value string
      opts.mutation_results = value
    end,
  },
  {
    name = "--help",
    aliases = { "-h" },
    description = "show this help",
    set = function(opts)
      opts.help = true
    end,
  },
}

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

--- @type table<string, NtfFlag>
local by_token = {}
for _, flag in ipairs(M.flags) do
  by_token[flag.name] = flag
  for _, alias in ipairs(flag.aliases or {}) do
    by_token[alias] = flag
  end
end

--- @return string
local function usage()
  local width = 0
  local labels = {}
  for _, flag in ipairs(M.flags) do
    local label = M.flag_label(flag)
    table.insert(labels, label)
    width = math.max(width, #label)
  end

  local lines = { "Usage: ntf [options] [spec-file-or-dir...]", "", "Options:" }
  for i, flag in ipairs(M.flags) do
    table.insert(lines, ("  %-" .. (width + 2) .. "s%s"):format(labels[i], flag.description))
  end
  table.insert(lines, "")
  table.insert(lines, "With no paths, runs the *_spec.lua files under ./spec.")
  return table.concat(lines, "\n")
end

--- @param argv string[]
--- @return NtfOptions|string # parsed options table, or an error message string
function M.parse(argv)
  local opts = {
    paths = {},
    timeout = 60000,
    filter = nil,
    list = false,
    jobs = nil,
    test_hook = nil,
    global_hook = nil,
    exclude_code = {},
    exclude_spec = {},
    coverage = false,
    coverage_file = "luacov.stats.out",
    mutation = false,
    mutation_path = nil,
    mutation_strict = nil,
    mutation_matrix = nil,
    mutation_config = nil,
    mutation_verify_baseline = false,
    mutation_results = "ntf-mutation.json",
    help = false,
  }

  local seen = {}
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    local token, inline = arg:match("^(%-%-[%w-]+)=(.*)$")
    token = token or arg
    --- @type NtfFlag?
    local flag = by_token[token]
    if flag and flag.value == nil and inline ~= nil then
      flag = nil
    end
    if flag then
      local value = inline
      if flag.value ~= nil and not flag.optional and value == nil then
        i = i + 1
        value = argv[i]
        if value == nil then
          return "missing value for " .. token .. "\n\n" .. usage()
        end
      end
      if flag.optional and value == "" then
        value = nil
      end
      local err = flag.set(opts, value)
      if err then
        return err
      end
      seen[flag.name] = true
    elseif arg:sub(1, 1) == "-" then
      return "unknown option: " .. arg .. "\n\n" .. usage()
    else
      table.insert(opts.paths, arg)
    end
    i = i + 1
  end

  if opts.help then
    return opts
  end
  if #opts.paths == 0 then
    if vim.fn.isdirectory("spec") == 1 then
      opts.paths = { "spec" }
    else
      return "no spec paths given\n\n" .. usage()
    end
  end
  if opts.filter and not pcall(string.find, "", opts.filter) then
    return "invalid --filter pattern: " .. opts.filter
  end
  if opts.test_hook and vim.fn.filereadable(opts.test_hook) == 0 then
    return "--test-hook module not found: " .. opts.test_hook
  end
  if opts.global_hook and vim.fn.filereadable(opts.global_hook) == 0 then
    return "--global-hook module not found: " .. opts.global_hook
  end
  if #opts.exclude_code > 0 and not (opts.coverage or opts.mutation) then
    return "--exclude-code requires --coverage or --mutation"
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
  local mutation_only_flag = opts.mutation_strict
    or opts.mutation_matrix
    or opts.mutation_config
    or opts.mutation_verify_baseline
  if not opts.mutation and (mutation_only_flag or seen["--mutation-results"]) then
    return "--mutation-strict, --mutation-matrix, --mutation-config, --mutation-verify-baseline, and --mutation-results require --mutation"
  end
  if opts.mutation_verify_baseline and not opts.mutation_config then
    return "--mutation-verify-baseline requires --mutation-config"
  end
  if opts.mutation_verify_baseline and (opts.mutation_strict or opts.mutation_matrix) then
    return "--mutation-verify-baseline runs the baseline entries alone, so --mutation-strict and --mutation-matrix have nothing to report"
  end
  if
    opts.mutation_path
    and vim.fn.filereadable(opts.mutation_path) == 0
    and vim.fn.isdirectory(opts.mutation_path) == 0
  then
    return "--mutation path not found: " .. opts.mutation_path
  end
  if opts.mutation_config and vim.fn.filereadable(opts.mutation_config) == 0 then
    return "--mutation-config file not found: " .. opts.mutation_config
  end

  return opts
end

M.usage = usage

return M
