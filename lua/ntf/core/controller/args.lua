-- Command line parsing for the controller (`ntf [options] <paths...>`).
local M = {}

--- @class NtfOptions
--- @field paths string[] spec files or directories
--- @field timeout integer default per-worker timeout in ms (0 disables)
--- @field filter string? Lua pattern; keep only matching leaves
--- @field jobs integer? max parallel workers
--- @field shuffle boolean randomize test order
--- @field seed integer? seed used with shuffle
--- @field setup string? Lua script run in each worker before any spec
--- @field help boolean show usage and exit

--- Supported flags in display order. Single source of truth shared by `usage()`
--- and the doc generation, so the flag list is never duplicated.
--- @type { name: string, description: string }[]
M.flags = {
  { name = "--timeout=MS", description = "kill a worker after MS milliseconds (default: 60000; 0 disables)" },
  { name = "--filter=PATTERN", description = "run only tests whose full name matches the Lua pattern" },
  { name = "--jobs=N", description = "max parallel nvim workers (default: cpu count)" },
  { name = "--shuffle", description = "randomize test order" },
  { name = "--seed=N", description = "seed used with --shuffle (default: time based)" },
  { name = "--setup=PATH", description = "run a Lua script in each worker before any spec" },
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
    shuffle = false,
    seed = nil,
    setup = nil,
    help = false,
  }

  -- Value-taking flags, each storing its value into `opts`. Both the
  -- `--name=VALUE` and the `--name VALUE` (space-separated) forms are accepted.
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
    ["--seed"] = function(v)
      opts.seed = tonumber(v)
    end,
    ["--setup"] = function(v)
      opts.setup = v
    end,
  }

  local i = 1
  while i <= #argv do
    local arg = argv[i]
    local name, inline = arg:match("^(%-%-[%w-]+)=(.*)$")
    name = name or arg
    if arg == "-h" or arg == "--help" then
      opts.help = true
    elseif arg == "--shuffle" then
      opts.shuffle = true
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
  if opts.setup and vim.fn.filereadable(opts.setup) == 0 then
    return "--setup script not found: " .. opts.setup
  end

  return opts
end

M.usage = usage

return M
