local M = {}

--- @type table<string, true> the node kinds that hold statements of their own
local HOLDS_STATEMENTS = {
  chunk = true,
  block = true,
}

--- @type table<string, true> the node kinds one statement of a block is spelled as
local STATEMENT = {
  variable_declaration = true,
  assignment_statement = true,
  function_call = true,
  function_declaration = true,
  if_statement = true,
  while_statement = true,
  repeat_statement = true,
  for_statement = true,
  do_statement = true,
  return_statement = true,
  break_statement = true,
  goto_statement = true,
  label_statement = true,
  empty_statement = true,
}

--- @class NtfCoverageStatement one statement of the source, where a counter goes
--- @field row integer 1-based row it starts on
--- @field byte integer 0-based byte it starts at

--- @param src string the full source text
--- @return NtfCoverageStatement[] # every statement, in the order it is written
function M.statements(src)
  local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()

  local found = {}
  local function walk(node)
    local holds_statements = HOLDS_STATEMENTS[node:type()]
    for child in node:iter_children() do
      if holds_statements and STATEMENT[child:type()] then
        local row, _, byte = child:start()
        table.insert(found, { row = row + 1, byte = byte })
      end
      walk(child)
    end
  end
  walk(root)

  return found
end

--- @param src string the full source text
--- @return table<integer, true> # coverable lines, 1-based: the row each statement starts on, which is where its counter goes
function M.coverable(src)
  local lines = {}
  for _, statement in ipairs(M.statements(src)) do
    lines[statement.row] = true
  end
  return lines
end

--- @param node TSNode
--- @return integer[] # the 1-based row of the statement the node belongs to; empty where it belongs to none
function M.anchor_rows(node)
  local current = node --- @type TSNode?
  while current do
    local parent = current:parent()
    if parent and HOLDS_STATEMENTS[parent:type()] and STATEMENT[current:type()] then
      return { (current:start()) + 1 }
    end
    current = parent
  end
  return {}
end

return M
