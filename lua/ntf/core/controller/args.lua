local M = {}

-- WHY: a `not_applied` or `equivalent` mutant says nothing about the tests, so
-- gating on it would fail a run for something no spec can fix.
-- NOT: every status the mutation report knows about.
--- @type string[] the mutant statuses `--mutation-strict` can gate on; the bare flag selects all of them
local STRICT_CATEGORIES = { "survived", "no_coverage" }

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
--- @field mutation_baseline string? known-equivalent mutants file (JSON)
--- @field mutation_results string mutation results output path (JSON)
--- @field help boolean show usage and exit

--- @type { name: string, description: string }[]
M.flags = {
  { name = "--timeout=MS", description = "kill a worker after MS milliseconds (default: 60000; 0 disables)" },
  { name = "--filter=PATTERN", description = "run only tests whose full name matches the Lua pattern" },
  {
    name = "--list",
    description = "list the tests without running them (with --mutation, run the tests and list the mutants with coverage)",
  },
  { name = "--jobs=N", description = "max parallel nvim workers (default: cpu count)" },
  {
    name = "--test-hook=FILE",
    description = "run a Lua module providing setup/teardown around each test, in its worker",
  },
  {
    name = "--global-hook=FILE",
    description = "run a Lua module providing setup/teardown once around the whole run, in the launcher process",
  },
  {
    name = "--exclude-code=PATH",
    description = "leave a file or directory out of the code --coverage measures and --mutation mutates (repeatable)",
  },
  {
    name = "--exclude-spec=PATH",
    description = "skip a spec file or directory when discovering tests (repeatable)",
  },
  {
    name = "--coverage[=FILE]",
    description = "measure line coverage; write luacov.stats.out (or FILE) and print a summary",
  },
  {
    name = "--mutation[=PATH]",
    description = "mutation-test the covered code (only under PATH, if given) once the tests pass",
  },
  {
    name = "--mutation-strict[=LIST]",
    description = "exit non-zero when any mutant is survived or no-coverage (LIST restricts the gate to a comma-separated subset)",
  },
  {
    name = "--mutation-baseline=FILE",
    description = "leave the known-equivalent mutants listed in FILE out of the score; exit non-zero when an entry matches nothing",
  },
  { name = "--mutation-results=FILE", description = "mutation results output path (default: ntf-mutation.json)" },
  { name = "-h, --help", description = "show this help" },
}

--- @return string
local function usage()
  local width = 0
  for _, flag in ipairs(M.flags) do
    width = math.max(width, #flag.name)
  end

  local lines = { "Usage: ntf [options] [spec-file-or-dir...]", "", "Options:" }
  for _, flag in ipairs(M.flags) do
    table.insert(lines, ("  %-" .. (width + 2) .. "s%s"):format(flag.name, flag.description))
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
    mutation_baseline = nil,
    mutation_results = "ntf-mutation.json",
    help = false,
  }

  local value_flags = {
    ["--timeout"] = function(v)
      opts.timeout = tonumber(v)
    end,
    ["--filter"] = function(v)
      opts.filter = v
    end,
    ["--jobs"] = function(v)
      opts.jobs = tonumber(v)
    end,
    ["--test-hook"] = function(v)
      opts.test_hook = v
    end,
    ["--global-hook"] = function(v)
      opts.global_hook = v
    end,
    ["--exclude-code"] = function(v)
      table.insert(opts.exclude_code, v)
    end,
    ["--exclude-spec"] = function(v)
      table.insert(opts.exclude_spec, v)
    end,
    ["--mutation-baseline"] = function(v)
      opts.mutation_baseline = v
    end,
    ["--mutation-results"] = function(v)
      opts.mutation_results = v
    end,
  }

  local i = 1
  while i <= #argv do
    local arg = argv[i]
    local name, inline = arg:match("^(%-%-[%w-]+)=(.*)$")
    name = name or arg
    if arg == "-h" or arg == "--help" then
      opts.help = true
    elseif arg == "--list" then
      opts.list = true
    elseif name == "--coverage" then
      opts.coverage = true
      if inline ~= nil and inline ~= "" then
        opts.coverage_file = inline
      end
    elseif name == "--mutation" then
      opts.mutation = true
      if inline ~= nil and inline ~= "" then
        opts.mutation_path = inline
      end
    elseif name == "--mutation-strict" then
      opts.mutation_strict = {}
      if inline == nil or inline == "" then
        for _, status in ipairs(STRICT_CATEGORIES) do
          opts.mutation_strict[status] = true
        end
      else
        for status in inline:gmatch("[^,]+") do
          if not vim.tbl_contains(STRICT_CATEGORIES, status) then
            return "invalid --mutation-strict category: "
              .. status
              .. " (expected "
              .. table.concat(STRICT_CATEGORIES, ", ")
              .. ")"
          end
          opts.mutation_strict[status] = true
        end
      end
    elseif value_flags[name] then
      local v = inline
      if v == nil then
        i = i + 1
        v = argv[i]
      end
      if v == nil then
        return "missing value for " .. name .. "\n\n" .. usage()
      end
      value_flags[name](v)
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
  if type(opts.timeout) ~= "number" or opts.timeout < 0 then
    return "invalid --timeout value (expected milliseconds >= 0)"
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
  if
    not opts.mutation
    and (opts.mutation_strict or opts.mutation_baseline or opts.mutation_results ~= "ntf-mutation.json")
  then
    return "--mutation-strict, --mutation-baseline, and --mutation-results require --mutation"
  end
  if
    opts.mutation_path
    and vim.fn.filereadable(opts.mutation_path) == 0
    and vim.fn.isdirectory(opts.mutation_path) == 0
  then
    return "--mutation path not found: " .. opts.mutation_path
  end
  if opts.mutation_baseline and vim.fn.filereadable(opts.mutation_baseline) == 0 then
    return "--mutation-baseline file not found: " .. opts.mutation_baseline
  end

  return opts
end

M.usage = usage

return M
