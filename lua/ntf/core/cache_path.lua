local M = {}

--- @param kind string what the file holds, which is the directory it is filed under
--- @param extension string
--- @return string # a file named for the working directory, so two projects never share one
local function path(kind, extension)
  local name = vim.fs.normalize(vim.fn.getcwd()):gsub("[/\\:]", "%%")
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", kind, name .. extension)
end

--- @return string
function M.schedule()
  return path("schedule", ".json")
end

--- @return string
function M.mutation_results()
  return path("mutation", ".json")
end

--- @return string
function M.coverage_stats()
  return path("coverage", ".out")
end

return M
