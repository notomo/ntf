local absolute = require("ntf.core.path").absolute

local M = {}

--- @return string # the directory every cache file is filed under
function M.root()
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf")
end

--- @param kind string what the file holds, which is the directory it is filed under
--- @param extension string
--- @param named_for string? the path the file is named for (default: the working directory)
--- @return string # a file named for that path, so two of them never share one
local function path(kind, extension, named_for)
  local name = absolute(named_for or vim.fn.getcwd()):gsub("[/\\:]", "%%")
  return vim.fs.joinpath(M.root(), kind, name .. extension)
end

--- @param file string a cache file named for a path
--- @return string # that path, spelled as absolute() spells one: the separators back from the `%` they were filed as, and a drive letter given back its colon
function M.named_for(file)
  local decoded = vim.fn.fnamemodify(file, ":t:r"):gsub("%%", "/")
  return (decoded:gsub("^(%a)//", "%1:/"))
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

--- @param nonce string the worker it carries the payload of, so two of them never share one file
--- @return string
function M.payload(nonce)
  return vim.fs.joinpath(M.root(), "payload", nonce .. ".json")
end

--- @param source string the file it holds the instrumented copy of
--- @return string # a path no `.lua` of its own, so that a cache directory inside a project is never taken for code under test
function M.instrumented(source)
  return path("instrumented", ".instrumented", source)
end

return M
