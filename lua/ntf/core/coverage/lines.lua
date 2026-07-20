-- Decides which never-hit lines should still count as coverable (so they show
-- as missed). LuaJIT's line hook attributes instructions to lines in ways that
-- a per-line text heuristic cannot model (a table constructor collapses onto its
-- opening line, consecutive bare `local`s merge onto the first, a closure's
-- creation lands on its closing `end`). So the set of coverable lines is derived
-- from the treesitter syntax tree instead: a line is coverable only when a node
-- that actually receives a hit begins on it.
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

--- Whether a value's evaluation is dominated by creating a closure, whose hit
--- lands on the closing `end` rather than the statement's opening line. True for
--- a bare `function() ... end` and for a short-circuit `a or function() ... end`
--- (the operand closure, not the opener, carries the hit).
--- @param node TSNode a value expression
--- @return integer? # 0-based row of the closing `end`, nil when not closure-dominated
local function closure_hit_row(node)
  local kind = node:type()
  if kind == "function_definition" then
    return (node:end_())
  end
  if kind == "binary_expression" then
    for child in node:iter_children() do
      if child:named() then
        local row = closure_hit_row(child)
        if row then
          return row
        end
      end
    end
  end
  return nil
end

--- The rows a statement's hit lands on when its only values are closure-dominated:
--- their creation hit lands on each closing `end`, not the statement's line, so
--- the header must not count as coverable.
--- @param node TSNode an `assignment_statement` or `return_statement`
--- @return integer[]? # 0-based rows, nil when any value receives its hit on the statement's own line
local function only_closure_rows(node)
  for child in node:iter_children() do
    if child:type() == "expression_list" then
      local rows = {}
      local total = 0
      for value in child:iter_children() do
        if value:named() then
          total = total + 1
          local row = closure_hit_row(value)
          if not row then
            return nil
          end
          table.insert(rows, row)
        end
      end
      return total > 0 and rows or nil
    end
  end
  return nil
end

--- @param node TSNode
--- @return integer? # 0-based row where the hit lands when `node` executes, nil
--- when the node is not a hit receiver of its own
local function hit_row(node)
  local kind = node:type()
  if kind == "function_call" then
    -- Anchor on the `(` (the `arguments` child), where the call's hit lands,
    -- not the call node's start: a multi-line method chain begins on the
    -- receiver line (`vim` alone) whose row never receives a hit.
    for child in node:iter_children() do
      if child:type() == "arguments" then
        return (child:start())
      end
    end
    return (node:start())
  end
  if kind == "assignment_statement" or kind == "return_statement" then
    if only_closure_rows(node) then
      return nil
    end
    return (node:start())
  end
  if EXEC_STMT[kind] then
    return (node:start())
  end
  return nil
end

--- @param src string the full source text
--- @return table<integer, true> # coverable lines, 1-based
function M.coverable(src)
  local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()
  local lines = {}
  local function walk(node)
    local row = hit_row(node)
    if row then
      lines[row + 1] = true
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

--- The rows where the line hook fires when the innermost hit-receiving construct
--- enclosing `node` executes. A line can hold code and still never receive a hit
--- of its own (a constant table field folds into the constructor's template), so
--- coverage of such a node is only visible on these rows.
--- @param node TSNode
--- @return integer[] # 1-based rows; empty when no hit-receiving ancestor exists
function M.anchor_rows(node)
  local current = node --- @type TSNode?
  while current do
    local row = hit_row(current)
    if row then
      return { row + 1 }
    end
    local kind = current:type()
    if kind == "assignment_statement" or kind == "return_statement" then
      -- `hit_row` said no because every value is a closure: the hits land on
      -- their closing `end` rows instead.
      return vim.tbl_map(function(end_row)
        return end_row + 1
      end, only_closure_rows(current) or {})
    end
    current = current:parent()
  end
  return {}
end

return M
