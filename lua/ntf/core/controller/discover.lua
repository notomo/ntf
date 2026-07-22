local M = {}

--- @param path string
--- @return string # normalized absolute path
local function absolute(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
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
      for _, file in ipairs(vim.fn.glob(path .. "/**/*_spec.lua", true, true)) do
        add(file)
      end
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

return M
