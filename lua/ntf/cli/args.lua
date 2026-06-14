-- Command line parsing for the controller (`ntf [options] <paths...>`).
local M = {}

local ISOLATE_LEVELS = { file = true, describe = true, it = true }

--- Supported flags in display order. Single source of truth shared by `usage()`
--- and the doc generation, so the flag list is never duplicated.
--- @type { name: string, description: string }[]
M.flags = {
  { name = "--isolate=LEVEL", description = "process split granularity: file|describe|it (default: it)" },
  { name = "--filter=PATTERN", description = "run only tests whose full name matches the Lua pattern" },
  { name = "--jobs=N", description = "max parallel nvim workers (default: cpu count)" },
  { name = "--shuffle", description = "randomize test order" },
  { name = "--seed=N", description = "seed used with --shuffle (default: time based)" },
  { name = "--json", description = "emit machine-readable JSON instead of the text report" },
  { name = "--no-color", description = "disable ANSI colors" },
  { name = "--no-progress", description = "disable the streaming progress dots on stderr" },
  { name = "--slow=MS", description = "report tests slower than MS milliseconds" },
  { name = "-h, --help", description = "show this help" },
}

--- @return string
local function usage()
  local width = 0
  for _, flag in ipairs(M.flags) do
    width = math.max(width, #flag.name)
  end

  local lines = { "Usage: ntf [options] <spec-file-or-dir>...", "", "Options:" }
  for _, flag in ipairs(M.flags) do
    table.insert(lines, ("  %-" .. (width + 2) .. "s%s"):format(flag.name, flag.description))
  end
  return table.concat(lines, "\n")
end

--- @param argv string[]
--- @return table|string # parsed options table, or an error message string
function M.parse(argv)
  local opts = {
    paths = {},
    isolate = vim.env.NTF_ISOLATE or "it",
    filter = nil,
    jobs = nil,
    shuffle = false,
    seed = nil,
    json = false,
    color = nil,
    no_progress = false,
    slow = nil,
    help = false,
  }

  local function value(arg, prefix)
    local eq = arg:match("^" .. prefix .. "=(.*)$")
    return eq
  end

  for _, arg in ipairs(argv) do
    if arg == "-h" or arg == "--help" then
      opts.help = true
    elseif arg == "--shuffle" then
      opts.shuffle = true
    elseif arg == "--json" then
      opts.json = true
    elseif arg == "--no-color" then
      opts.color = false
    elseif arg == "--no-progress" then
      opts.no_progress = true
    elseif value(arg, "%-%-isolate") then
      opts.isolate = value(arg, "%-%-isolate")
    elseif value(arg, "%-%-filter") then
      opts.filter = value(arg, "%-%-filter")
    elseif value(arg, "%-%-jobs") then
      opts.jobs = tonumber(value(arg, "%-%-jobs"))
    elseif value(arg, "%-%-seed") then
      opts.seed = tonumber(value(arg, "%-%-seed"))
    elseif value(arg, "%-%-slow") then
      opts.slow = tonumber(value(arg, "%-%-slow"))
    elseif arg:sub(1, 1) == "-" then
      return "unknown option: " .. arg .. "\n\n" .. usage()
    else
      table.insert(opts.paths, arg)
    end
  end

  if opts.help then
    return opts
  end
  if #opts.paths == 0 then
    return "no spec paths given\n\n" .. usage()
  end
  if not ISOLATE_LEVELS[opts.isolate] then
    return "invalid --isolate level: " .. tostring(opts.isolate)
  end
  if opts.filter and not pcall(string.find, "", opts.filter) then
    return "invalid --filter pattern: " .. opts.filter
  end

  return opts
end

M.usage = usage

return M
