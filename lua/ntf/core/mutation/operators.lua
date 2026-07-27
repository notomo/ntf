local lines = require("ntf.core.coverage.lines")

local M = {}

--- @class NtfMutantSite : NtfMutantSplice
--- @field operator string mutation operator name
--- @field row integer 1-based start line
--- @field col integer 0-based start column
--- @field end_row integer 1-based end line
--- @field end_col integer 0-based end column, exclusive
--- @field anchor_rows integer[] 1-based rows where the hit lands when the site executes (see `lines.anchor_rows`)

-- WHY: the grammar names an anonymous operator token after its own text, so the
-- node type is already the spelling to swap on.
-- NOT: `vim.treesitter.get_node_text`, a source slice per candidate node.
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
  -- WHY: the `not` token's own range stops at the keyword, so splicing it out
  -- leaves the space before the operand behind.
  -- NOT: a splice of `node:child(0)`, the `not` token alone.
  if operand and node:child(0):type() == "not" then
    local text = vim.treesitter.get_node_text(node, src)
    table.insert(sites, site(node, "drop-not", text, vim.treesitter.get_node_text(operand, src)))
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
