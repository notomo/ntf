local cache_path = require("ntf.core.cache_path")

local M = {}

--- @class NtfCacheKind one directory of the cache and what makes a file of it one nothing reads
--- @field name string the directory
--- @field extension string what its files end with
--- @field stale fun(file: string): boolean whether nothing reads the file any more
--- @field reason string what a removed file of this kind was, as the report says it

--- @param file string a cache file named for a path
--- @return boolean # whether that path is gone
local function named_for_gone(file)
  return vim.uv.fs_stat(cache_path.named_for(file)) == nil
end

--- @type NtfCacheKind[]
local KINDS = {
  {
    name = "schedule",
    extension = ".json",
    stale = named_for_gone,
    reason = "named for a working directory that is gone",
  },
  {
    name = "mutation",
    extension = ".json",
    stale = named_for_gone,
    reason = "named for a working directory that is gone",
  },
  {
    name = "coverage",
    extension = ".out",
    stale = named_for_gone,
    reason = "named for a working directory that is gone",
  },
  {
    name = "instrumented",
    extension = ".instrumented",
    stale = named_for_gone,
    reason = "copies of sources that are gone",
  },
  {
    name = "payload",
    extension = ".json",
    stale = function()
      return true
    end,
    reason = "left by workers that never took them",
  },
}

--- @class NtfCacheCleaned what cleaning one kind came to
--- @field name string the directory
--- @field removed integer
--- @field kept integer
--- @field reason string what the removed files were

--- @param root string the directory the cache files are filed under
--- @return NtfCacheCleaned[] # one per kind, in the order the report lists them
function M.clean(root)
  local cleaned = {}
  for _, kind in ipairs(KINDS) do
    local dir = vim.fs.joinpath(root, kind.name)
    local removed, kept = 0, 0
    for name, type in vim.fs.dir(dir) do
      if type == "file" and vim.endswith(name, kind.extension) then
        local file = vim.fs.joinpath(dir, name)
        if kind.stale(file) and os.remove(file) then
          removed = removed + 1
        else
          kept = kept + 1
        end
      end
    end
    table.insert(cleaned, { name = kind.name, removed = removed, kept = kept, reason = kind.reason })
  end
  return cleaned
end

--- @param root string the directory the cache files are filed under
--- @param cleaned NtfCacheCleaned[]
--- @return string # one line per kind, after the directory they are under
function M.report(root, cleaned)
  local lines = { root }
  for _, entry in ipairs(cleaned) do
    table.insert(
      lines,
      ("  %s: removed %d of %d (%s)"):format(entry.name, entry.removed, entry.removed + entry.kept, entry.reason)
    )
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
