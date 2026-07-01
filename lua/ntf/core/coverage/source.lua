-- Source analysis shared by the coverage summary and the buffer decoration:
-- deciding which never-hit lines should still count as coverable (so they show
-- as missed). LuaJIT's line hook attributes instructions to lines in ways that
-- a per-line text heuristic cannot model (a table constructor collapses onto its
-- opening line, consecutive bare `local`s merge onto the first, a closure's
-- creation lands on its closing `end`). So the set of coverable lines is derived
-- from the treesitter syntax tree instead: a line is coverable only when a node
-- that actually receives a hit begins on it. Combined with the recorded hits
-- (the callers union them in), this never pushes a file above 100%.
local M = {}

-- Statement nodes that execute on their own opening line, so a hit lands there.
local EXEC_STMT = {
  if_statement = true,
  while_statement = true,
  repeat_statement = true,
  for_numeric_statement = true,
  for_generic_statement = true,
  break_statement = true,
  goto_statement = true,
}

--- Whether a statement's only values are closures: their creation hit lands on
--- the closing `end`, not this line, so the header must not count as coverable.
--- @param node TSNode an `assignment_statement` or `return_statement`
--- @return boolean
local function only_closures(node)
  for child in node:iter_children() do
    if child:type() == "expression_list" then
      local total, closures = 0, 0
      for value in child:iter_children() do
        if value:named() then
          total = total + 1
          if value:type() == "function_definition" then
            closures = closures + 1
          end
        end
      end
      return total > 0 and total == closures
    end
  end
  return false
end

--- The 1-based lines that should count as coverable for `src`.
--- @param src string the full source text
--- @return table<integer, true>
function M.coverable_lines(src)
  local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()
  local lines = {}
  local function walk(node)
    local kind = node:type()
    if kind == "function_call" then
      -- Anchor on the `(` (the `arguments` child), where the call's hit lands,
      -- not the call node's start: a multi-line method chain begins on the
      -- receiver line (`vim` alone) whose row never receives a hit.
      local anchor = node
      for child in node:iter_children() do
        if child:type() == "arguments" then
          anchor = child
          break
        end
      end
      lines[anchor:start() + 1] = true
    else
      local coverable = EXEC_STMT[kind]
      if kind == "assignment_statement" or kind == "return_statement" then
        coverable = not only_closures(node)
      end
      if coverable then
        lines[node:start() + 1] = true
      end
    end
    for child in node:iter_children() do
      if child:named() then
        walk(child)
      end
    end
  end
  walk(root)
  return lines
end

return M
