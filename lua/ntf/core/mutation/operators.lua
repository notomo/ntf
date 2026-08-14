local lines = require("ntf.core.coverage.lines")

local M = {}

--- @class NtfMutantSite : NtfMutantSplice
--- @field operator string mutation operator name
--- @field row integer 1-based start line
--- @field col integer 0-based start column
--- @field end_row integer 1-based end line
--- @field end_col integer 0-based end column, exclusive
--- @field anchor_rows integer[] 1-based rows where the hit lands when the site executes (see `lines.anchor_rows`)

--- @class NtfMutationOperator
--- @field name string the site's `operator`, as reported and as written in a baseline entry
--- @field example string source whose every site is this operator's, mutated to show the change

--- @type NtfMutationOperator[] # in the order the document lists them
M.operators = {
  {
    name = "swap-relational",
    example = "local _ = a <= b",
  },
  {
    name = "swap-logical",
    example = "local _ = a and b",
  },
  {
    name = "swap-arithmetic",
    example = "local _ = a + b * c % d ^ e",
  },
  {
    name = "swap-boolean",
    example = "local _ = true",
  },
  {
    name = "drop-not",
    example = "local _ = not a",
  },
  {
    name = "drop-negation",
    example = "local _ = -a",
  },
  {
    name = "perturb-number",
    example = "local _ = 1",
  },
  {
    name = "perturb-length",
    example = "local _ = #a",
  },
  {
    name = "force-branch",
    example = "if a then end",
  },
  {
    name = "force-loop",
    example = "while a do end",
  },
  {
    name = "drop-call",
    example = "f()",
  },
  {
    name = "drop-assignment",
    example = "a.b = c",
  },
  {
    name = "drop-return-value",
    example = "function f() return a end",
  },
}

--- @type table<string, NtfMutationOperator> # the same operators, keyed by the name a report prints and a config writes
M.by_name = {}
for _, operator in ipairs(M.operators) do
  M.by_name[operator.name] = operator
end

--- @alias NtfMutationOperatorSelection "all"|string[] the operators a run enumerates mutants for

--- @param value any the operators a config or one of its entries declares
--- @param needs string what the message says the value has to be, when it is neither "all" nor an array
--- @return string? # what is wrong with it
function M.validate_selection(value, needs)
  if value == "all" then
    return nil
  end
  if type(value) ~= "table" or #value == 0 then
    return needs
  end
  for _, name in ipairs(value) do
    if type(name) ~= "string" or not M.by_name[name] then
      return ("names an operator no run produces: %s"):format(vim.inspect(name))
    end
  end
  return nil
end

--- @param selection NtfMutationOperatorSelection
--- @return fun(operator: string): boolean # whether the run enumerates that operator's mutants
function M.adopted(selection)
  if selection == "all" then
    return function()
      return true
    end
  end
  local listed = selection --[[@as string[] ]]
  local names = {} --- @type table<string, true>
  for _, name in ipairs(listed) do
    names[name] = true
  end
  return function(operator)
    return names[operator] == true
  end
end

local BINARY_SWAPS = {
  ["=="] = { operator = "swap-relational", to = "~=" },
  ["~="] = { operator = "swap-relational", to = "==" },
  ["<"] = { operator = "swap-relational", to = "<=" },
  ["<="] = { operator = "swap-relational", to = "<" },
  [">"] = { operator = "swap-relational", to = ">=" },
  [">="] = { operator = "swap-relational", to = ">" },
  ["and"] = { operator = "swap-logical", to = "or" },
  ["or"] = { operator = "swap-logical", to = "and" },
  ["+"] = { operator = "swap-arithmetic", to = "-" },
  ["-"] = { operator = "swap-arithmetic", to = "+" },
  ["*"] = { operator = "swap-arithmetic", to = "/" },
  ["/"] = { operator = "swap-arithmetic", to = "*" },
  ["%"] = { operator = "swap-arithmetic", to = "*" },
  ["^"] = { operator = "swap-arithmetic", to = "*" },
}

--- @param _ string the whole unary expression
--- @param operand string what the operator is applied to
--- @return string # the operand alone, the operator dropped
local function dropped(_, operand)
  return operand
end

--- @param text string the whole `#` expression
--- @return string # the count one short, parenthesized so that whatever the expression sits under takes all of it
local function one_shorter(text)
  return ("(%s - 1)"):format(text)
end

--- @type table<string, { operator: string, mutate: fun(text: string, operand: string): string }> # the unary operators, and what a site of one puts in place of the whole expression
local UNARY_MUTATIONS = {
  ["not"] = { operator = "drop-not", mutate = dropped },
  ["-"] = { operator = "drop-negation", mutate = dropped },
  ["#"] = { operator = "perturb-length", mutate = one_shorter },
}

local BOOLEAN_SWAPS = {
  ["true"] = "false",
  ["false"] = "true",
}

--- @type table<string, true> # the node types whose children are statements
local STATEMENT_BLOCK = {
  block = true,
  chunk = true,
}

local DROPPED_STATEMENT = "do end"

local DROPPED_RETURN_VALUE = "nil"

--- @type table<string, true> # value kinds whose own operator already owns the return of a single one of them
local OWNED_LITERAL = {
  ["nil"] = true,
  ["true"] = true,
  ["false"] = true,
  number = true,
}

-- WHY: a return the chunk itself answers with is the module, not an answer a
-- caller weighs, so emptying it fails every user of the module at once instead
-- of asking any test for the precision the operator is about.
-- NOT: taking every return and leaving the module ones to a baseline, which
-- would spend a trial per file to learn only that some spec requires it.
--- @type table<string, true> # the node types a return answers for
local RETURNING_FUNCTION = {
  function_definition = true,
  function_declaration = true,
}

-- WHY: forcing a decision to each outcome is the branch-coverage analogue a line
-- hook cannot reach; a loop only gets the outcome that terminates it, since the
-- other spins forever to prove nothing a coverage hit does not already, while
-- burning a whole trial timeout. `while` exits on false and `repeat` on true.
-- NOT: emitting both for a loop and leaning on the runner's trial timeout to
-- bound the infinite one.
--- @type table<string, { operator: string, forces: string[] }> # the decision node types, and what their condition is forced to
local FORCED_CONDITION = {
  if_statement = { operator = "force-branch", forces = { "false", "true" } },
  elseif_statement = { operator = "force-branch", forces = { "false", "true" } },
  while_statement = { operator = "force-loop", forces = { "false" } },
  repeat_statement = { operator = "force-loop", forces = { "true" } },
}

--- @type table<string, string> # the `for` clause types, and the clause of theirs that iterates none
local FORCE_EMPTY_LOOP = {
  for_numeric_clause = "_ = 1, 0",
  for_generic_clause = "_ in pairs({})",
}

--- @param node TSNode
--- @param operator string
--- @param replacement string
--- @param original string
--- @return NtfMutantSite
local function site(node, operator, original, replacement)
  local row, col, start_byte = node:start()
  local end_row, end_col, end_byte = node:end_()
  return {
    operator = operator,
    row = row + 1,
    col = col,
    end_row = end_row + 1,
    end_col = end_col,
    start_byte = start_byte,
    end_byte = end_byte,
    original = original,
    replacement = replacement,
    anchor_rows = lines.anchor_rows(node),
  }
end

--- @param node TSNode a `binary_expression`
--- @param sites NtfMutantSite[]
local function binary_sites(node, sites)
  for child in node:iter_children() do
    local swap = not child:named() and BINARY_SWAPS[child:type()]
    if swap then
      table.insert(sites, site(child, swap.operator, child:type(), swap.to))
    end
  end
end

--- @param node TSNode a `unary_expression`
--- @param src string
--- @param sites NtfMutantSite[]
local function unary_sites(node, src, sites)
  local operand = node:named_child(0)
  local mutation = UNARY_MUTATIONS[node:child(0):type()]
  if operand and mutation then
    local text = vim.treesitter.get_node_text(node, src)
    table.insert(
      sites,
      site(node, mutation.operator, text, mutation.mutate(text, vim.treesitter.get_node_text(operand, src)))
    )
  end
end

--- @param node TSNode a `function_call`
--- @param src string the full source text
--- @param sites NtfMutantSite[]
local function drop_call_sites(node, src, sites)
  local parent = assert(node:parent())
  if STATEMENT_BLOCK[parent:type()] then
    table.insert(sites, site(node, "drop-call", vim.treesitter.get_node_text(node, src), DROPPED_STATEMENT))
  end
end

-- WHY: a `local` declaration parses as an assignment_statement under a
-- variable_declaration, so the block parent is what keeps one out: deleting it
-- would leave every later mention of the name reading a global instead, which
-- is a rewrite of the scope rather than of the store.
-- NOT: matching on the `local` keyword, which the assignment_statement the
-- declaration wraps does not carry.
--- @param node TSNode an `assignment_statement`
--- @param src string the full source text
--- @param sites NtfMutantSite[]
local function drop_assignment_sites(node, src, sites)
  local parent = assert(node:parent())
  if STATEMENT_BLOCK[parent:type()] then
    table.insert(sites, site(node, "drop-assignment", vim.treesitter.get_node_text(node, src), DROPPED_STATEMENT))
  end
end

--- @param node TSNode a `return_statement`
--- @return boolean # whether it answers for a function, not for the chunk itself
local function answers_for_function(node)
  local current = node:parent()
  while current do
    if RETURNING_FUNCTION[current:type()] then
      return true
    end
    current = current:parent()
  end
  return false
end

--- @param node TSNode a `return_statement`
--- @param src string the full source text
--- @param sites NtfMutantSite[]
local function drop_return_value_sites(node, src, sites)
  if not answers_for_function(node) then
    return
  end
  local values
  for child in node:iter_children() do
    if child:type() == "expression_list" then
      values = child
    end
  end
  if not values then
    return
  end
  if not values:named_child(1) and OWNED_LITERAL[values:named_child(0):type()] then
    return
  end
  local text = vim.treesitter.get_node_text(values, src)
  table.insert(sites, site(values, "drop-return-value", text, DROPPED_RETURN_VALUE))
end

--- @param node TSNode a decision node whose condition is forced to each outcome, or a `for` clause forced to iterate none
--- @param src string the full source text
--- @param sites NtfMutantSite[]
local function forced_sites(node, src, sites)
  local empty = FORCE_EMPTY_LOOP[node:type()]
  if empty then
    table.insert(sites, site(node, "force-loop", vim.treesitter.get_node_text(node, src), empty))
    return
  end
  local forced = FORCED_CONDITION[node:type()]
  if not forced then
    return
  end
  local cond = node:field("condition")[1]
  if BOOLEAN_SWAPS[cond:type()] then
    return
  end
  local text = vim.treesitter.get_node_text(cond, src)
  for _, to in ipairs(forced.forces) do
    table.insert(sites, site(cond, forced.operator, text, to))
  end
end

--- @param src string the full source text
--- @return NtfMutantSite[] # sorted by start byte
function M.enumerate(src)
  local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()
  local sites = {}

  local function walk(node)
    local kind = node:type()
    if kind == "binary_expression" then
      binary_sites(node, sites)
    elseif kind == "unary_expression" then
      unary_sites(node, src, sites)
    elseif kind == "function_call" then
      drop_call_sites(node, src, sites)
    elseif kind == "assignment_statement" then
      drop_assignment_sites(node, src, sites)
    elseif kind == "return_statement" then
      drop_return_value_sites(node, src, sites)
    elseif BOOLEAN_SWAPS[kind] then
      table.insert(sites, site(node, "swap-boolean", kind, BOOLEAN_SWAPS[kind]))
    elseif kind == "number" then
      local text = vim.treesitter.get_node_text(node, src)
      local number = tonumber(text)
      if number then
        table.insert(sites, site(node, "perturb-number", text, tostring(number + 1)))
      end
    end

    forced_sites(node, src, sites)

    for child in node:iter_children() do
      if child:named() then
        walk(child)
      end
    end
  end
  walk(root)

  table.sort(sites, function(a, b)
    if a.start_byte ~= b.start_byte then
      return a.start_byte < b.start_byte
    end
    return a.operator < b.operator
  end)
  return sites
end

return M
