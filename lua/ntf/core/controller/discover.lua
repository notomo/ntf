local M = {}

--- @param paths string[] CLI paths (spec files or directories)
--- @return string[] # sorted absolute *_spec.lua paths
function M.specs(paths)
  local files = {}
  local seen = {}

  local function add(path)
    local full = vim.fn.fnamemodify(path, ":p")
    if not seen[full] then
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
