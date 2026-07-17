local M = {}

--- @class NtfOptions
--- @field paths string[] spec files or directories
--- @field timeout integer default per-worker timeout in ms (0 disables)
--- @field filter string? Lua pattern; keep only matching leaves
--- @field jobs integer? max parallel workers
--- @field schedule_cache string? per-test duration cache path (nil = under the nvim cache dir)
--- @field test_hook string? Lua module returning optional setup/teardown, run once per test around its worker's spec
--- @field global_hook string? Lua module returning optional setup/teardown, run once in the launcher around the whole run
--- @field exclude_code string[] files or directories to leave out of the code under test
--- @field coverage boolean measure line coverage of the code under test
--- @field coverage_file string stats output path (luacov.stats.out format)
--- @field mutation boolean mutation-test the covered code after a passing run
--- @field mutation_path string? restrict the mutated files to this file or directory
--- @field mutation_threshold number? minimum mutation score, in percent
--- @field mutation_baseline string? known-equivalent mutants file (JSON)
--- @field mutation_results string mutation results output path (JSON)
--- @field help boolean show usage and exit

--- @type { name: string, description: string }[]
M.flags = {
  { name = "--timeout=MS", description = "kill a worker after MS milliseconds (default: 60000; 0 disables)" },
  { name = "--filter=PATTERN", description = "run only tests whose full name matches the Lua pattern" },
  { name = "--jobs=N", description = "max parallel nvim workers (default: cpu count)" },
  {
    name = "--schedule-cache=FILE",
    description = "per-test duration cache used to run the slowest tests first (default: under the nvim cache dir)",
  },
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
    name = "--coverage[=FILE]",
    description = "measure line coverage; write luacov.stats.out (or FILE) and print a summary",
  },
  {
    name = "--mutation[=PATH]",
    description = "mutation-test the covered code (only under PATH, if given) once the tests pass",
  },
  { name = "--mutation-threshold=N", description = "exit non-zero when the mutation score is below N percent" },
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
    jobs = nil,
    schedule_cache = nil,
    test_hook = nil,
    global_hook = nil,
    exclude_code = {},
    coverage = false,
    coverage_file = "luacov.stats.out",
    mutation = false,
    mutation_path = nil,
    mutation_threshold = nil,
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
    ["--schedule-cache"] = function(v)
      opts.schedule_cache = v
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
    ["--mutation-threshold"] = function(v)
      opts.mutation_threshold = tonumber(v)
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
  if
    not opts.mutation
    and (opts.mutation_threshold or opts.mutation_baseline or opts.mutation_results ~= "ntf-mutation.json")
  then
    return "--mutation-threshold, --mutation-baseline, and --mutation-results require --mutation"
  end
  if
    opts.mutation_threshold
    and (type(opts.mutation_threshold) ~= "number" or opts.mutation_threshold < 0 or opts.mutation_threshold > 100)
  then
    return "invalid --mutation-threshold value (expected a percentage in 0..100)"
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
