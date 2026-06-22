-- Splits one spec file's test tree into work items (each runs in one process).
--
-- Granularity ("file" | "describe" | "it") sets the default split; any node
-- marked via `describe.isolate` / `it.isolate` forces its subtree into its own
-- item regardless of granularity (the outermost isolate ancestor wins).
local tree = require("ntf.core.tree")

local M = {}

local function each_leaf(root, visit)
  local function walk(node, ancestors)
    for _, child in ipairs(node.children or {}) do
      if tree.is_leaf(child) then
        visit(child, ancestors)
      else
        local next_ancestors = vim.list_extend(vim.list_extend({}, ancestors), { child })
        walk(child, next_ancestors)
      end
    end
  end
  walk(root, {})
end

--- @param root NtfNode tree root
--- @param granularity string "file" | "describe" | "it"
--- @return { node_ids: string[], timeout: integer? }[] items
function M.split(root, granularity)
  local order = {}
  local groups = {}

  -- An item's timeout comes from the single node that defines it (the isolation
  -- unit): the isolate ancestor, or the leaf/describe when it is itself the unit.
  -- A per-node timeout therefore only takes effect when that node is its own unit;
  -- inner timeouts are ignored once several leaves share one process (see doc.lua).
  local function push(key, id, unit)
    if not groups[key] then
      groups[key] = { node_ids = {}, timeout = unit and unit.timeout or nil }
      table.insert(order, key)
    end
    table.insert(groups[key].node_ids, id)
  end

  each_leaf(root, function(leaf, ancestors)
    local isolate_node
    for _, ancestor in ipairs(ancestors) do
      if ancestor.isolate then
        isolate_node = ancestor
        break
      end
    end
    if not isolate_node and leaf.isolate then
      isolate_node = leaf
    end

    local key, unit
    if isolate_node then
      key = "isolate:" .. isolate_node.id
      unit = isolate_node
    elseif granularity == "it" then
      key = "it:" .. leaf.id
      unit = leaf
    elseif granularity == "describe" then
      unit = ancestors[1]
      key = "describe:" .. (unit and unit.id or "")
    else
      key = "file"
    end
    push(key, leaf.id, unit)
  end)

  local items = {}
  for _, key in ipairs(order) do
    table.insert(items, { node_ids = groups[key].node_ids, timeout = groups[key].timeout })
  end
  return items
end

return M
