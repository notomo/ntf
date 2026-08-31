local absolute = require("ntf.core.path").absolute

local M = {}

--- @param kind string what the file holds, which is the directory it is filed under
--- @param extension string
--- @param named_for string? the path the file is named for (default: the working directory)
--- @return string # a file named for that path, so two of them never share one
local function path(kind, extension, named_for)
  local name = absolute(named_for or vim.fn.getcwd()):gsub("[/\\:]", "%%")
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

--- @param source string the file it holds the instrumented copy of
--- @return string # a path no `.lua` of its own, so that a cache directory inside a project is never taken for code under test
function M.instrumented(source)
  return path("instrumented", ".instrumented", source)
end

return M
