-- WHY: its own module, because the worker applies mutants with it.
-- NOT: part of operators.lua, whose require would chain-load coverage/lines into
-- every worker before the loader hook is installed and, ntf being self-hosted,
-- leave mutants of those modules unappliable.
local M = {}

--- @class NtfMutantSplice a byte range of a source and what to put in its place
--- @field start_byte integer 0-based byte offset
--- @field end_byte integer 0-based byte offset, exclusive
--- @field original string the replaced text
--- @field replacement string

--- @param src string the full source text
--- @param splice NtfMutantSplice
--- @return string? # nil when the source no longer matches the splice
function M.apply(src, splice)
  if src:sub(splice.start_byte + 1, splice.end_byte) ~= splice.original then
    return nil
  end
  return src:sub(1, splice.start_byte) .. splice.replacement .. src:sub(splice.end_byte + 1)
end

return M
