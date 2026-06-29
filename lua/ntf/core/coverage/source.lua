-- Source-line heuristics shared by the coverage summary and the buffer
-- decoration: deciding whether a never-hit line should still count as coverable.
local M = {}

-- Lines that carry no executable code: blank, comment-only, or a line whose only
-- content is a block terminator (`end`, `else`, `until ...`, a closing `)`/`}`).
-- Anything a line hook actually recorded is always counted regardless, so this
-- only affects lines that were never hit (the heuristic can never push a file
-- above 100%).
--- @param text string a source line
--- @return boolean
function M.is_code(text)
  local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" or trimmed:match("^%-%-") then
    return false
  end
  if trimmed:match("^end[%)%]},;]*$") or trimmed == "else" or trimmed:match("^until%f[%W]") then
    return false
  end
  if trimmed:match("^[%)%]}%s,;]+$") then
    return false
  end
  return true
end

return M
