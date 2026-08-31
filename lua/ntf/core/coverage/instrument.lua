local statements = require("ntf.core.coverage.lines").statements
local cache_path = require("ntf.core.cache_path")
local write = require("ntf.core.write")

local M = {}

--- @type string what the cached copy carries the digest of the source it was made from behind
local MARKER = "\n--ntf:"

--- @param src string the full source text
--- @return string # the same source, counting each statement it runs into the table the chunk is called with, every line of it left where it was
function M.transform(src)
  local parts = { "local __ntf_counts=...;return function(...)" }

  local previous = 0
  for _, statement in ipairs(statements(src)) do
    table.insert(parts, src:sub(previous + 1, statement.byte))
    table.insert(parts, ("__ntf_counts[%d]=(__ntf_counts[%d] or 0)+1;"):format(statement.row, statement.row))
    previous = statement.byte
  end
  table.insert(parts, src:sub(previous + 1))
  table.insert(parts, "\nend")

  return table.concat(parts)
end

--- @param path string absolute file path
--- @return string? # its content
local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

--- @param path string normalized absolute file path
--- @param suffix string what the copy of the source as it is now ends with
--- @return string? # the instrumented copy an earlier run left, nil when it is of another version of the source
local function cached(path, suffix)
  local content = read_file(cache_path.instrumented(path))
  if content and content:sub(-#suffix) == suffix then
    return content
  end
  return nil
end

--- @param path string normalized absolute file path
--- @return function? # the chunk taking the table to count into and returning the module's own body, nil when the file is not one this can instrument
function M.chunk(path)
  local src = read_file(path)
  if not src then
    return nil
  end

  local suffix = MARKER .. vim.fn.sha256(src)
  local text = cached(path, suffix)
  if not text then
    text = M.transform(src) .. suffix
    write.file(cache_path.instrumented(path), text)
  end

  return (loadstring(text, "@" .. path))
end

return M
