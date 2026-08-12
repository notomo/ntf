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
--- @field description string what a test has to do to detect the mutant
--- @field example string source whose every site is this operator's, mutated to show the change

--- @type NtfMutationOperator[] # in the order the document lists them
M.operators = {
  {
    name = "swap-relational",
    description = "a test has to exercise the boundary value the two disagree on",
    example = "return a <= b",
  },
  {
    name = "swap-logical",
    description = "a test has to reach operands the two connectives disagree on",
    example = "return a and b",
  },
  {
    name = "swap-arith",
    description = "a test has to exercise a right operand the two disagree on",
    example = "return a + b * c % d ^ e",
  },
  {
    name = "flip-boolean",
    description = "a test has to depend on the value, not merely execute the line",
    example = "return true",
  },
  {
    name = "drop-not",
    description = "a test has to reach the branch the negation decides",
    example = "return not a",
  },
  {
    name = "drop-neg",
    description = "a test has to exercise a nonzero operand and depend on its sign",
    example = "return -a",
  },
  {
    name = "perturb-number",
    description = "a test has to depend on the exact value, not on its being non-zero",
    example = "return 1",
  },
  {
    name = "force-branch",
    description = "each side needs a test; a loop is only forced to the outcome that exits",
    example = "if a then end",
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
  ["+"] = { operator = "swap-arith", to = "-" },
  ["-"] = { operator = "swap-arith", to = "+" },
  ["*"] = { operator = "swap-arith", to = "/" },
  ["/"] = { operator = "swap-arith", to = "*" },
  ["%"] = { operator = "swap-arith", to = "*" },
  ["^"] = { operator = "swap-arith", to = "*" },
}

local UNARY_DROPS = {
  ["not"] = "drop-not",
  ["-"] = "drop-neg",
}

local BOOLEAN_FLIPS = {
  ["true"] = "false",
  ["false"] = "true",
}

-- WHY: forcing a decision to each outcome is the branch-coverage analogue a line
-- hook cannot reach; a loop only gets the outcome that terminates it, since the
-- other spins forever to prove nothing a coverage hit does not already, while
-- burning a whole trial timeout. `while` exits on false, `repeat` on true.
-- NOT: emitting both for a loop and leaning on the runner's trial timeout to
-- bound the infinite one.
local FORCE_BRANCH = {
  if_statement = { "false", "true" },
  elseif_statement = { "false", "true" },
  while_statement = { "false" },
  repeat_statement = { "true" },
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
  local operator = UNARY_DROPS[node:child(0):type()]
  if operand and operator then
    local text = vim.treesitter.get_node_text(node, src)
    table.insert(sites, site(node, operator, text, vim.treesitter.get_node_text(operand, src)))
  end
end

--- @param node TSNode a decision node whose condition is forced to each outcome
--- @param src string the full source text
--- @param sites NtfMutantSite[]
local function force_branch_sites(node, src, sites)
  local forces = FORCE_BRANCH[node:type()]
  if not forces then
    return
  end
  local cond = node:field("condition")[1]
  if BOOLEAN_FLIPS[cond:type()] then
    return
  end
  local text = vim.treesitter.get_node_text(cond, src)
  for _, to in ipairs(forces) do
    table.insert(sites, site(cond, "force-branch", text, to))
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
    elseif BOOLEAN_FLIPS[kind] then
      table.insert(sites, site(node, "flip-boolean", kind, BOOLEAN_FLIPS[kind]))
    elseif kind == "number" then
      local text = vim.treesitter.get_node_text(node, src)
      local number = tonumber(text)
      if number then
        table.insert(sites, site(node, "perturb-number", text, tostring(number + 1)))
      end
    end

    force_branch_sites(node, src, sites)

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
