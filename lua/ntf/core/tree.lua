local M = {}

--- @class NtfTrace
--- @field source string chunk source (e.g. "@/path/to/spec.lua")
--- @field line integer? 1-based line the node was declared on

--- @class NtfNode
--- @field type "root"|"describe"|"it"|"pending"
--- @field name string
--- @field id string node id ("" for root; dotted path otherwise)
--- @field children NtfNode[]? child nodes (root/describe only)
--- @field before_each (fun())[]? before_each hooks (root/describe only)
--- @field after_each (fun())[]? after_each hooks (root/describe only)
--- @field timeout integer? kill this it's process after N ms (it only)
--- @field trace NtfTrace? declaration site
--- @field fn fun()? test body (it only)
--- @field load_error any? load/build error captured on this node (root/describe)

M.PENDING = "__ntf_pending__"

local stack = {} ---@type NtfNode[]

local finally_collector = nil

local function current()
  return stack[#stack]
end

local function add_child(node)
  local parent = current()
  table.insert(parent.children, node)
  local prefix = parent.id == "" and "" or parent.id .. "."
  node.id = prefix .. tostring(#parent.children)
  return node
end

--- @return NtfTrace?
local function trace_of(fn, level)
  local info
  if type(fn) == "function" then
    info = debug.getinfo(fn, "S")
    return { source = info.source, line = info.linedefined }
  end
  info = debug.getinfo(level or 3, "Sl")
  if not info then
    return nil
  end
  return { source = info.source, line = info.currentline }
end

--- @param name string
--- @param fn fun()
--- @return NtfNode node
local function new_describe(name, fn)
  local node = {
    type = "describe",
    name = name,
    id = nil,
    children = {},
    before_each = {},
    after_each = {},
    trace = trace_of(fn),
  }
  add_child(node)
  table.insert(stack, node)
  local ok, err = pcall(fn)
  table.remove(stack)
  if not ok then
    node.load_error = err
  end
  return node
end

--- @param name string
--- @param fn fun()
--- @param opts NtfItOption?
--- @return NtfNode node
local function new_it(name, fn, opts)
  local node = {
    type = "it",
    name = name,
    fn = fn,
    trace = trace_of(fn),
    timeout = opts and opts.timeout or nil,
  }
  return add_child(node)
end

--- @param name string
--- @param fn fun()? optional body (ignored; pending is never executed)
--- @return NtfNode node
local function new_pending(name, fn)
  if not current() then
    error({ [M.PENDING] = true, message = name }, 0)
  end
  local node = {
    type = "pending",
    name = name,
    fn = nil,
    trace = trace_of(fn, 3),
  }
  return add_child(node)
end

local function add_hook(field)
  return function(fn)
    table.insert(current()[field], fn)
  end
end

M.describe = new_describe
M.it = new_it
M.pending = new_pending
M.before_each = add_hook("before_each")
M.after_each = add_hook("after_each")
M.finally = function(fn)
  if finally_collector then
    table.insert(finally_collector, fn)
  end
end

-- WHY: an execute may nest inside a running test, whose own collector has to
-- survive it.
-- NOT: clearing the collector on the way out.
--- @param fn fun() runs with a fresh `finally` collector installed; must not throw, the caller catches errors inside
--- @return (fun())[] collected finally callbacks
function M.collect_finallies(fn)
  local saved = finally_collector
  finally_collector = {}
  fn()
  local collected = finally_collector
  finally_collector = saved
  return collected
end

-- WHY: the children a describe collected before its body errored are an
-- arbitrary prefix of what the file meant to declare, so the describe is
-- reported as one error instead.
-- NOT: descending into them and running what did get collected.
--- @param node NtfNode
--- @return boolean # true for `it`, `pending`, and any node whose body errored during build
function M.is_leaf(node)
  return node.type == "it" or node.type == "pending" or node.load_error ~= nil
end

--- @param file_path string
--- @return NtfNode root node (with .children, .load_error)
function M.build(file_path)
  local root = {
    type = "root",
    name = "",
    id = "",
    children = {},
    before_each = {},
    after_each = {},
  }
  stack = { root }

  local chunk, load_err = loadfile(file_path)
  if not chunk then
    root.load_error = load_err
    stack = {}
    return root
  end

  local ok, err = pcall(chunk)
  if not ok then
    root.load_error = err
  end
  stack = {}
  return root
end

--- @param root NtfNode
--- @return fun():(NtfNode?, string[]?) # iterator yielding each leaf with its describe/it name chain
function M.iter_leaves(root)
  local result = {}
  local function walk(node, names)
    for _, child in ipairs(node.children or {}) do
      local child_names = vim.list_extend(vim.list_extend({}, names), { child.name })
      if M.is_leaf(child) then
        table.insert(result, { node = child, names = child_names })
      else
        walk(child, child_names)
      end
    end
  end
  walk(root, {})
  local i = 0
  return function()
    i = i + 1
    local entry = result[i]
    if not entry then
      return nil
    end
    return entry.node, entry.names
  end
end

--- @param names string[] describe/it name chain
--- @return string
function M.full_name(names)
  return table.concat(
    vim.tbl_filter(function(s)
      return s ~= nil and s ~= ""
    end, names or {}),
    " "
  )
end

return M
