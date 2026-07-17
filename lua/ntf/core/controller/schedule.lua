local tree = require("ntf.core.tree")

local M = {}

local VERSION = 1

--- @class NtfScheduleEntry
--- @field ms number wall time of the last run
--- @field status string result status of the last run

--- @class NtfScheduleCache last-run data per test, for slowest-first dispatch
--- @field version integer
--- @field files table<string, table<string, NtfScheduleEntry>> relative spec path -> full test name -> entry

--- @param cwd string
--- @return string
local function normalize(cwd)
  return (vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p")):gsub("/$", ""))
end

--- @param file string absolute spec path
--- @param cwd string normalized absolute working directory
--- @return string
local function relative(file, cwd)
  file = vim.fs.normalize(file)
  if file:sub(1, #cwd + 1) == cwd .. "/" then
    return file:sub(#cwd + 2)
  end
  return file
end

--- @return string
function M.default_path()
  local name = normalize(vim.fn.getcwd()):gsub("[/\\:]", "%%")
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "schedule", name .. ".json")
end

--- @param path string
--- @return NtfScheduleCache
function M.load(path)
  local empty = { version = VERSION, files = {} }
  local f = io.open(path, "r")
  if not f then
    return empty
  end
  local blob = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, blob)
  if not ok or type(decoded) ~= "table" or decoded.version ~= VERSION or type(decoded.files) ~= "table" then
    return empty
  end
  return decoded
end

--- @param cache NtfScheduleCache
--- @param file string absolute spec path
--- @param cwd string normalized absolute working directory
--- @param names string[]
--- @return NtfScheduleEntry?
local function entry_of(cache, file, cwd, names)
  local by_name = cache.files[relative(file, cwd)]
  return by_name and by_name[tree.full_name(names)] or nil
end

--- @param items NtfWorkItem[]
--- @param cache NtfScheduleCache
--- @param cwd string working directory
--- @return NtfWorkItem[]
function M.order(items, cache, cwd)
  cwd = normalize(cwd)
  local keyed = {}
  for index, item in ipairs(items) do
    local entry = entry_of(cache, item.file, cwd, item.names)
    table.insert(keyed, { item = item, ms = entry and entry.ms or math.huge, index = index })
  end
  table.sort(keyed, function(a, b)
    if a.ms ~= b.ms then
      return a.ms > b.ms
    end
    return a.index < b.index
  end)
  return vim.tbl_map(function(k)
    return k.item
  end, keyed)
end

--- @param path string
--- @param cache NtfScheduleCache
--- @param results NtfResult[]
--- @param cwd string working directory
function M.save(path, cache, results, cwd)
  cwd = normalize(cwd)
  for _, result in ipairs(results) do
    if result.duration and result.file then
      local key = relative(result.file, cwd)
      local by_name = cache.files[key] or {}
      by_name[tree.full_name(result.names)] = { ms = result.duration * 1000, status = result.status }
      cache.files[key] = by_name
    end
  end

  pcall(function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = assert(io.open(path, "w"))
    f:write(vim.json.encode(cache))
    f:close()
  end)
end

return M
