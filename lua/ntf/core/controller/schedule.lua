local tree = require("ntf.core.tree")
local write = require("ntf.core.write")
local normalize = require("ntf.core.path").normalize
local absolute = require("ntf.core.path").absolute

local M = {}

local VERSION = 1

--- @class NtfScheduleEntry
--- @field ms number wall time of the last run
--- @field status string result status of the last run

--- @class NtfScheduleCache last-run data per test, for slowest-first dispatch
--- @field version integer
--- @field files table<string, table<string, NtfScheduleEntry>> relative spec path -> full test name -> entry

--- @param file string absolute spec path
--- @param cwd string normalized absolute working directory
--- @return string
local function relative(file, cwd)
  file = normalize(file)
  if file:sub(1, #cwd + 1) == cwd .. "/" then
    return file:sub(#cwd + 2)
  end
  return file
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
  cwd = absolute(cwd)
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
--- @param results NtfResult[]
--- @param cwd string working directory
--- @param whole_suite boolean? the run ran every test the project has, so the entries it does not report are of tests that are gone
function M.save(path, results, cwd, whole_suite)
  cwd = absolute(cwd)

  -- WHY: the cache is read again here, rather than the run writing back the one
  -- it ordered its items from, so that a run which saved while this one was
  -- still testing keeps the entries it saved.
  -- NOT: passing that ordering cache in, which carries the file as it stood
  -- before this run started and puts it back over the other run's.
  local cache = whole_suite and { version = VERSION, files = {} } or M.load(path)
  for _, result in ipairs(results) do
    if result.duration and result.file then
      local key = relative(result.file, cwd)
      local by_name = cache.files[key] or {}
      by_name[tree.full_name(result.names)] = { ms = result.duration * 1000, status = result.status }
      cache.files[key] = by_name
    end
  end

  pcall(write.file, path, vim.json.encode(cache))
end

return M
