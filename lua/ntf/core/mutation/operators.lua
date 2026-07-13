local M = {}

--- @class NtfMutantSplice a byte range of a source and what to put in its place
--- @field start_byte integer 0-based byte offset
--- @field end_byte integer 0-based byte offset, exclusive
--- @field original string the replaced text
--- @field replacement string

--- @class NtfMutantSite : NtfMutantSplice
--- @field operator string mutation operator name
--- @field row integer 1-based start line
--- @field col integer 0-based start column
--- @field end_row integer 1-based end line
--- @field end_col integer 0-based end column, exclusive

-- Keyed by node type rather than by `get_node_text`: the grammar names an
-- anonymous operator token by its own text.
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
  local operand
  for child in node:iter_children() do
    if child:named() then
      operand = child
    end
  end
  -- The whole `not x` is replaced by `x`, rather than deleting the `not` token
  -- alone, so no dangling whitespace is left behind.
  if operand and node:child(0):type() == "not" then
    local text = vim.treesitter.get_node_text(node, src)
    table.insert(sites, site(node, "drop-not", text, vim.treesitter.get_node_text(operand, src)))
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
