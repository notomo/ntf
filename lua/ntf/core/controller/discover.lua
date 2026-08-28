local is_hidden = require("ntf.core.path").is_hidden
local normalize = require("ntf.core.path").normalize

local M = {}

-- WHY: vim.fs reads a "$VAR" component of a path as the variable it names, and the plain=true that
-- turns that off is on Neovim master only, so a released Neovim finds another directory's specs or
-- none at all. vim.fn.fnamemodify(), vim.fn.simplify() and vim.fn.readdir() read a path as a path
-- on every version.
-- NOT: vim.fs.normalize(path, { plain = true }) here and vim.fs.dir(dir, { plain = true }) in collect()

--- @param path string
--- @return string # normalized absolute path
local function absolute(path)
  return normalize(vim.fn.simplify(vim.fn.fnamemodify(path, ":p")))
end

--- @param dir string normalized absolute directory
--- @param add fun(path: string) takes each spec file found
local function collect(dir, add)
  for _, name in ipairs(vim.fn.readdir(dir)) do
    local file = vim.fs.joinpath(dir, name)
    if not is_hidden(name) then
      if vim.fn.getftype(file) == "dir" then
        collect(file, add)
      elseif name:match("_spec%.lua$") and vim.fn.filereadable(file) == 1 then
        add(file)
      end
    end
  end
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
