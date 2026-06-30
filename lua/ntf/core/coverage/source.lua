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
  -- A multi-line function/closure header (`...function(args)` with the body on
  -- following lines). LuaJIT attributes the closure-creating instruction to the
  -- closing `end`, not this header, so the header never receives a line-hook
  -- event even when the surrounding statement runs. Counting it would flag a
  -- spurious miss; the matching `end` (or a body line) carries the real hit.
  if trimmed:match("function%s*%([^()]*%)$") then
    return false
  end
  -- An explicit `= nil` assignment. Assigning nil to a table field (or default)
  -- emits no bytecode at all, so the line can never receive a line-hook event;
  -- counting it would flag a permanent spurious miss. (`== nil` comparisons and
  -- `return nil` still execute, so they are intentionally not matched.)
  if trimmed:match("[^=~<>]=%s*nil%s*[,;]?$") then
    return false
  end
  return true
end

return M
