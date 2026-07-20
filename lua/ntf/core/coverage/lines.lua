local M = {}

local EXEC_STMT = {
  if_statement = true,
  while_statement = true,
  repeat_statement = true,
  for_statement = true,
  break_statement = true,
  goto_statement = true,
}

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

--- @param node TSNode an `assignment_statement` or `return_statement`
--- @return integer[]? # 0-based rows, nil when any value receives its hit on the statement's own line
local function only_closure_rows(node)
  for child in node:iter_children() do
    if child:type() == "expression_list" then
      local rows = {}
      for value in child:iter_children() do
        if value:named() then
          local row = closure_hit_row(value)
          if not row then
            return nil
          end
          table.insert(rows, row)
        end
      end
      return rows[1] and rows or nil
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
