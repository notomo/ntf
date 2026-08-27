local tree = require("ntf.core.tree")
local rel_source = require("ntf.core.controller.report").rel_source

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

--- @param shared NtfSharedName[]
--- @return string # one line per name, so a file answers for every one of them at once
local function shared_name_message(shared)
  return table.concat(
    vim.tbl_map(function(entry)
      return ("%d tests share the full name %q: %s"):format(
        #entry.traces,
        entry.name,
        table.concat(vim.tbl_map(rel_source, entry.traces), ", ")
      )
    end, shared),
    "\n"
  )
end

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
      local shared = tree.shared_names(root)
      if #shared > 0 then
        table.insert(load_errors, { file = file, message = shared_name_message(shared) })
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
  end

  return items, load_errors
end

return M
