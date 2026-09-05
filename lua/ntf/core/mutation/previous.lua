local tree = require("ntf.core.tree")

local M = {}

--- @param path string normalized absolute path of the mutated file
--- @param mutant { row: integer, col: integer, operator: string, replacement: string }
--- @return string # what names that mutant across runs, its position and what it became
local function key(path, mutant)
  return ("%s\0%d\0%d\0%s\0%s"):format(path, mutant.row, mutant.col, mutant.operator, mutant.replacement)
end

--- @param path string
--- @return string # the file's content, empty for one that cannot be read
local function content_of(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local content = file:read("*a")
  file:close()
  return content
end

--- @class NtfMutationPrevious what the run before this one filed, read back
--- @field killer fun(mutant: NtfMutant): string? full name of the test that killed that mutant then, nil for one no run has killed
--- @field settled fun(mutant: NtfMutant, trials: NtfMutantTrial[]): string? that same test, for a mutant no file it is judged by has changed since; nil for every mutant this run has to score itself
--- @field digests fun(): table<string, string> what this run read of the files a verdict depends on, which is what the next run tells a change by

--- @param filed NtfMutationResults? what the run before this one filed, nil where no run has filed any
--- @param reuse boolean whether a verdict may be taken from it rather than scored again
--- @return NtfMutationPrevious
function M.new(filed, reuse)
  local before = filed and filed.digests or {}

  local killed_by = {} --- @type table<string, string>
  for path, records in pairs(filed and filed.files or {}) do
    for _, record in ipairs(records) do
      killed_by[key(path, record)] = record.killed_by
    end
  end

  --- @type table<string, string> the digest of every file asked for so far, taken once and kept
  local digests = setmetatable({}, {
    __index = function(self, path)
      local digest = vim.fn.sha256(content_of(path))
      rawset(self, path, digest)
      return digest
    end,
  })

  --- @param path string
  --- @return boolean # whether the file is byte for byte what the run before read
  local function unchanged(path)
    return before[path] == digests[path]
  end

  --- @param mutant NtfMutant
  --- @return string?
  local function killer(mutant)
    return killed_by[key(mutant.path, mutant)]
  end

  --- @param mutant NtfMutant
  --- @param trials NtfMutantTrial[]
  --- @return string?
  local function settled(mutant, trials)
    local same = unchanged(mutant.path)
    for _, trial in ipairs(trials) do
      -- WHY: every file a trial of this run reaches is digested however this
      -- mutant came out, since what this run files is what the next one tells a
      -- change by, not only what decided a verdict here.
      -- NOT: leaving the loop at the first change, which files no digest for the
      -- spec files after it and leaves the next run judging them changed.
      same = unchanged(trial.item.file) and same
    end
    if not (reuse and same) then
      return nil
    end

    local name = killer(mutant)
    for _, trial in ipairs(trials) do
      if tree.full_name(trial.item.names) == name then
        return name
      end
    end
    return nil
  end

  return {
    killer = killer,
    settled = settled,
    digests = function()
      return digests
    end,
  }
end

return M
