local M = {}

--- @param kind string what the file holds, which is the directory it is filed under
--- @param extension string
--- @param working_dir string? the directory the file is named for (default: the current one)
--- @return string # a file named for that directory, so two projects never share one
local function path(kind, extension, working_dir)
  local name = vim.fs.normalize(vim.fn.fnamemodify(working_dir or vim.fn.getcwd(), ":p")):gsub("[/\\:]", "%%")
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", kind, name .. extension)
end

--- @return string
function M.schedule()
  return path("schedule", ".json")
end

--- @param working_dir string?
--- @return string
function M.mutation_results(working_dir)
  return path("mutation", ".json", working_dir)
end

--- @param working_dir string?
--- @return string
function M.coverage_stats(working_dir)
  return path("coverage", ".out", working_dir)
end

return M
