-- Splits one spec file's test tree into work items. Every leaf (`it`/`pending`,
-- or a `describe` whose body errored) runs in its own process, so an item is
-- always a single leaf carrying that leaf's own timeout.
local tree = require("ntf.core.tree")

local M = {}

--- @param root NtfNode tree root
--- @return { node_ids: string[], timeout: integer? }[] items
function M.split(root)
  local items = {}
  for leaf in tree.iter_leaves(root) do
    table.insert(items, { node_ids = { leaf.id }, timeout = leaf.timeout })
  end
  return items
end

return M
