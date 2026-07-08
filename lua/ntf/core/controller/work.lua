local tree = require("ntf.core.tree")

local M = {}

--- @class NtfLoadError
--- @field file string spec file path
--- @field message string error message

--- @class NtfWorkItem one leaf, run in its own worker process
--- @field file string spec file path
--- @field node_id string leaf id
--- @field names string[] describe/it name chain
--- @field trace NtfTrace? declaration site
--- @field timeout integer? per-item timeout in ms from the leaf node

--- @param files string[]
--- @param filter string|nil Lua pattern; keep only leaves whose full name matches
--- @return NtfWorkItem[] items, NtfLoadError[] load_errors
function M.plan(files, filter)
  local items = {}
  local load_errors = {}

  for _, file in ipairs(files) do
    local root = tree.build(file)
    if root.load_error then
      table.insert(load_errors, { file = file, message = tostring(root.load_error) })
    else
      for leaf, names in tree.iter_leaves(root) do
        if not filter or tree.full_name(names):find(filter) ~= nil then
          table.insert(items, {
            file = file,
            node_id = leaf.id,
            names = names,
            trace = leaf.trace,
            timeout = leaf.timeout,
          })
        end
      end
    end
  end

  return items, load_errors
end

return M
