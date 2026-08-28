local is_hidden = require("ntf.core.path").is_hidden
local absolute = require("ntf.core.path").absolute
local walk = require("ntf.core.walk")

local M = {}

--- @param dir string normalized absolute directory
--- @param add fun(path: string) takes each spec file found
local function collect(dir, add)
  walk.files(dir, {
    descend = function(subdir)
      return not is_hidden(subdir)
    end,
    on_file = function(file)
      if file:match("_spec%.lua$") and not is_hidden(file) and vim.fn.filereadable(file) == 1 then
        add(file)
      end
    end,
  })
end

--- @param paths string[] CLI paths (spec files or directories)
--- @param exclude string[]? spec files or directories to skip
--- @return string[] # sorted absolute *_spec.lua paths
function M.specs(paths, exclude)
  local excluded = {} --- @type string[] normalized absolute exclude paths
  for _, path in ipairs(exclude or {}) do
    table.insert(excluded, absolute(path))
  end
  local function is_excluded(full)
    for _, prefix in ipairs(excluded) do
      if full == prefix or full:sub(1, #prefix + 1) == prefix .. "/" then
        return true
      end
    end
    return false
  end

  local files = {}
  local seen = {}

  local function add(path)
    local full = absolute(path)
    if not seen[full] and not is_excluded(full) then
      seen[full] = true
      table.insert(files, full)
    end
  end

  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 then
      collect(absolute(path), add)
    elseif vim.fn.filereadable(path) == 1 then
      if not path:match("_spec%.lua$") then
        error("not a *_spec.lua file: " .. path, 0)
      end
      add(path)
    else
      error("path not found: " .. path, 0)
    end
  end

  table.sort(files)
  return files
end

--- @return string[] # the paths a run discovers from when it names none; empty where the project holds no such directory
function M.default_paths()
  if vim.fn.isdirectory("spec") == 1 then
    return { "spec" }
  end
  return {}
end

--- @param files string[] the spec files a run discovered
--- @return boolean # whether they hold every spec the project has, which is what a run naming no path takes
function M.holds_every_spec(files)
  local defaults = M.default_paths()
  if #defaults == 0 then
    return false
  end

  local discovered = {}
  for _, file in ipairs(files) do
    discovered[file] = true
  end
  for _, file in ipairs(M.specs(defaults)) do
    if not discovered[file] then
      return false
    end
  end
  return true
end

return M
