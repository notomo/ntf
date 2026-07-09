local M = {}

--- @class NtfOptions
--- @field paths string[] spec files or directories
--- @field timeout integer default per-worker timeout in ms (0 disables)
--- @field filter string? Lua pattern; keep only matching leaves
--- @field jobs integer? max parallel workers
--- @field test_hook string? Lua module returning optional setup/teardown, run once per test around its worker's spec
--- @field global_hook string? Lua module returning optional setup/teardown, run once in the launcher around the whole run
--- @field coverage boolean measure line coverage of the code under test
--- @field coverage_file string stats output path (luacov.stats.out format)
--- @field help boolean show usage and exit

--- @type { name: string, description: string }[]
M.flags = {
  { name = "--timeout=MS", description = "kill a worker after MS milliseconds (default: 60000; 0 disables)" },
  { name = "--filter=PATTERN", description = "run only tests whose full name matches the Lua pattern" },
  { name = "--jobs=N", description = "max parallel nvim workers (default: cpu count)" },
  {
    name = "--test-hook=PATH",
    description = "run a Lua module providing setup/teardown around each test, in its worker",
  },
  {
    name = "--global-hook=PATH",
    description = "run a Lua module providing setup/teardown once around the whole run, in the launcher process",
  },
  {
    name = "--coverage[=FILE]",
    description = "measure line coverage; write luacov.stats.out (or FILE) and print a summary",
  },
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
    test_hook = nil,
    global_hook = nil,
    coverage = false,
    coverage_file = "luacov.stats.out",
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

  return opts
end

M.usage = usage

return M
