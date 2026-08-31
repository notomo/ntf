local is_hidden = require("ntf.core.path").is_hidden
local absolute = require("ntf.core.path").absolute
local walk = require("ntf.core.walk")
local instrument = require("ntf.core.coverage.instrument")

local M = {}

--- @class NtfCoverageMeasurement one measurement in progress
--- @field loader function the package loader it installed
--- @field data table<string, table<integer, integer>> the hits its instrumented files count, by row
--- @field previous { loadfile: function, dofile: function } the loaders it took the place of, which reach no instrumented copy

--- @type NtfCoverageMeasurement[] the measurements in progress, innermost last
local measurements = {}

--- @param paths string[] files or directories (any form)
--- @return string[] absolute prefixes: a directory keeps its trailing slash, so
--- it cannot also match a sibling whose name merely starts with it
function M.exclude_paths(paths)
  local prefixes = {}
  for _, path in ipairs(paths) do
    local abs = absolute(path)
    if vim.fn.isdirectory(path) == 1 then
      abs = abs .. "/"
    end
    table.insert(prefixes, abs)
  end
  return prefixes
end

--- @param path string normalized absolute path
--- @param cwd string normalized absolute working directory
--- @param excludes string[] absolute dir prefixes (each ending with "/") to skip
--- @return string|false the path to record under, or false
local function measured_path(path, cwd, excludes)
  local under_cwd = path == cwd or path:sub(1, #cwd + 1) == cwd .. "/"
  if not under_cwd or path:match("_spec%.lua$") then
    return false
  end
  for _, prefix in ipairs(excludes) do
    if path:sub(1, #prefix) == prefix then
      return false
    end
  end
  return path
end

--- @param path string absolute file path
--- @return boolean
function M.is_meta_file(path)
  local f = io.open(path, "r")
  if not f then
    return false
  end
  local first = f:read("*l")
  f:close()
  return first ~= nil and first:match("^%-%-%-?%s*@meta") ~= nil
end

--- @param cwd string working directory (any form)
--- @param excludes string[] absolute dir prefixes (each ending with "/") to skip
--- @return string[] normalized absolute paths, sorted
function M.measurable_files(cwd, excludes)
  cwd = absolute(cwd)
  local files = {}
  walk.files(cwd, {
    descend = function(dir)
      if is_hidden(dir) then
        return false
      end
      local prefix = dir .. "/"
      for _, exclude in ipairs(excludes) do
        if prefix:sub(1, #exclude) == exclude then
          return false
        end
      end
      return true
    end,
    on_file = function(file)
      if file:match("%.lua$") and not is_hidden(file) and vim.fn.filereadable(file) == 1 then
        local path = measured_path(file, cwd, excludes)
        if path and not M.is_meta_file(path) then
          table.insert(files, path)
        end
      end
    end,
  })
  table.sort(files)
  return files
end

--- @param cwd string normalized absolute working directory
--- @param excludes string[] absolute dir prefixes (each ending with "/") to skip
--- @param data table<string, table<integer, integer>> what the files it loads count their rows into
--- @return fun(path: string): function? # the file's chunk, counting the rows it runs; nil for a file that is not measured code
local function make_measure(cwd, excludes, data)
  return function(path)
    local measured = measured_path(absolute(path), cwd, excludes)
    if not measured then
      return nil
    end
    local chunk = instrument.chunk(measured)
    if not chunk then
      return nil
    end
    local counts = data[measured] or {}
    data[measured] = counts
    return chunk(counts)
  end
end

--- @param name string a module name
--- @return boolean # whether Neovim's own loader finds it in a `lua/` directory of the runtimepath, where it reads the file with the `loadfile` a measurement replaces
local function in_runtimepath(name)
  local relative = (name:gsub("%.", "/"))
  for _, pattern in ipairs({ ("lua/%s.lua"):format(relative), ("lua/%s/init.lua"):format(relative) }) do
    if vim.api.nvim_get_runtime_file(pattern, false)[1] then
      return true
    end
  end
  return false
end

--- @param measure fun(path: string): function?
--- @return function # a `package.loaders` entry for the modules Lua loads itself, which no replaced `loadfile` reaches
local function make_loader(measure)
  return function(name)
    if in_runtimepath(name) then
      return nil
    end
    local path = package.searchpath(name, package.path)
    return path and measure(path) or nil
  end
end

--- @param name string the name a loaded module is filed under
--- @param cwd string normalized absolute working directory
--- @param excludes string[] absolute dir prefixes (each ending with "/") to skip
--- @return boolean # whether requiring it anew would reach a measured file
local function measured_module(name, cwd, excludes)
  local relative = (name:gsub("%.", "/"))
  for _, candidate in ipairs({
    ("%s/lua/%s.lua"):format(cwd, relative),
    ("%s/lua/%s/init.lua"):format(cwd, relative),
  }) do
    if vim.uv.fs_stat(candidate) and measured_path(candidate, cwd, excludes) then
      return true
    end
  end
  return false
end

--- @param opts { cwd: string, excludes?: string[] }
function M.start(opts)
  local cwd = absolute(opts.cwd)
  local excludes = opts.excludes or {}

  local data = {}
  local measure = make_measure(cwd, excludes, data)

  local loader = make_loader(measure)
  table.insert(package.loaders, 2, loader)

  local previous = { loadfile = loadfile, dofile = dofile }
  _G.loadfile = function(path)
    local chunk = path and measure(path)
    if not chunk then
      return previous.loadfile(path)
    end
    return chunk
  end
  _G.dofile = function(path)
    local chunk = path and measure(path)
    if not chunk then
      return previous.dofile(path)
    end
    return chunk()
  end

  for name in pairs(package.loaded) do
    if measured_module(name, cwd, excludes) then
      package.loaded[name] = nil
    end
  end

  table.insert(measurements, { loader = loader, data = data, previous = previous })
end

--- @param data table<string, table<integer, integer>> hits by row
--- @return table<string, { max: integer, lines: table<string, integer> }> # the rows keyed by string, since vim.json.encode rejects the sparse array they would otherwise form
local function counted(data)
  local out = {}
  for path, counts in pairs(data) do
    local lines = {}
    local max = 0
    for row, hits in pairs(counts) do
      lines[tostring(row)] = hits
      max = math.max(max, row)
    end
    out[path] = { max = max, lines = lines }
  end
  return out
end

--- @return table<string, { max: integer, lines: table<string, integer> }> # the counts recorded
function M.stop()
  local measurement = table.remove(measurements)
  for index, loader in ipairs(package.loaders) do
    if loader == measurement.loader then
      table.remove(package.loaders, index)
      break
    end
  end
  _G.loadfile = measurement.previous.loadfile
  _G.dofile = measurement.previous.dofile
  return counted(measurement.data)
end

--- @param into table accumulator (same shape as `M.stop`'s return)
--- @param part table|nil one worker's counts, JSON-decoded, so its line keys are strings
function M.merge(into, part)
  for path, entry in pairs(part or {}) do
    local target = into[path]
    if not target then
      target = { max = 0, lines = {} }
      into[path] = target
    end
    for line, hits in pairs(entry.lines or {}) do
      local n = tonumber(line)
      if n then
        target.lines[n] = (target.lines[n] or 0) + hits
      end
    end
    target.max = math.max(target.max, tonumber(entry.max) or 0)
  end
end

return M
