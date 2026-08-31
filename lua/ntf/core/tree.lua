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

--- @type boolean? true while a test is running, which is what pending() aborts
local running_test

local function current()
  return stack[#stack]
end

--- @param what string the API the message answers for
--- @param group NtfNode? the group being declared into, nil once no spec file is being loaded
--- @return NtfNode
local function declaring(what, group)
  if not group then
    error(
      ("%s() outside a spec file being loaded: the tests are declared once, before any of them runs"):format(what),
      0
    )
  end
  return group
end

--- @param node NtfNode
--- @param parent NtfNode
local function add_child(node, parent)
  table.insert(parent.children, node)
  local prefix = parent.id == "" and "" or parent.id .. "."
  node.id = prefix .. tostring(#parent.children)
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
  add_child(node, declaring("describe", current()))
  table.insert(stack, node)
  local ok, err = pcall(fn)
  table.remove(stack)
  if not ok then
    node.load_error = err
  end
end

--- @param name string
--- @param fn fun()
--- @param opts NtfItOption?
local function new_it(name, fn, opts)
  local node = {
    type = "it",
    name = name,
    fn = fn,
    trace = trace_of(fn),
    timeout = opts and opts.timeout or nil,
  }
  add_child(node, declaring("it", current()))
end

--- @param group NtfNode? the group being declared into, nil once no spec file is being loaded
--- @param running boolean? true while a test is running, which pending() leaves pending instead
--- @param name string
--- @param fn fun()? optional body (ignored; pending is never executed)
local function new_pending(group, running, name, fn)
  if not group then
    if not running then
      error(
        "pending() outside a spec file being loaded and outside a running test: it declares a skipped test where the tests are declared, and leaves the running one pending from a before_each or a test body",
        0
      )
    end
    error({ [M.PENDING] = true, message = name }, 0)
  end
  local node = {
    type = "pending",
    name = name,
    fn = nil,
    trace = trace_of(fn, 3),
  }
  add_child(node, group)
end

local function add_hook(field)
  return function(fn)
    table.insert(declaring(field, current())[field], fn)
  end
end

--- @param collector (fun())[]? what the running test collects into, nil once no test is running
--- @param fn fun()
function M.collect_finally(collector, fn)
  if not collector then
    error(
      "finally() outside a running test: only a before_each or a test body registers one, since an after_each already runs after the callbacks",
      0
    )
  end
  table.insert(collector, fn)
end

M.describe = new_describe
M.it = new_it
--- @param name string pending reason
--- @param fn fun()? optional body (ignored; pending is never executed)
M.pending = function(name, fn)
  return new_pending(current(), running_test, name, fn)
end
M.before_each = add_hook("before_each")
M.after_each = add_hook("after_each")
M.finally = function(fn)
  M.collect_finally(finally_collector, fn)
end

--- @param running boolean? true while a test is running, which pending() leaves pending instead of declaring; nil until a run installs one
--- @return boolean? # the state it replaced, to put back once that run is over
function M.set_running(running)
  local saved = running_test
  running_test = running
  return saved
end

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

--- @param root NtfNode
--- @param node_id string
--- @return string? # the full name of the leaf holding that id, nil when the tree holds none
function M.leaf_name(root, node_id)
  for leaf, names in M.iter_leaves(root) do
    if leaf.id == node_id then
      return M.full_name(names)
    end
  end
end

--- @param root NtfNode
--- @return integer # how many tests the file declares
function M.leaf_count(root)
  local count = 0
  for _ in M.iter_leaves(root) do
    count = count + 1
  end
  return count
end

--- @param root NtfNode the tree this process built
--- @param node_id string the leaf the run asked this process for
--- @param planned_names string[] the name chain the run planned at that position
--- @param planned_count integer how many tests the file declared when the run was planned
--- @return string? # what this tree and the run's disagree on, nil when they are the same tree
function M.divergence(root, node_id, planned_names, planned_count)
  local planned = M.full_name(planned_names)
  local found = M.leaf_name(root, node_id)
  if found ~= planned then
    return ("this worker built a different tree than the run planned from: the run picked %q, this position holds %s"):format(
      planned,
      found and ("%q"):format(found) or "no test"
    )
  end

  local count = M.leaf_count(root)
  if count ~= planned_count then
    return ("this worker built a different tree than the run planned from: this position still holds %q, but the run planned %d tests from this file and this process declares %d"):format(
      planned,
      planned_count,
      count
    )
  end
end

--- @class NtfSharedName a full name more than one test of a file carries
--- @field name string the full name they share
--- @field traces NtfTrace[] where each was declared, in declaration order

--- @param root NtfNode
--- @return NtfSharedName[] # every name more than one leaf carries, first occurrence first
function M.shared_names(root)
  local traces_of = {} --- @type table<string, NtfTrace[]>
  local order = {} --- @type string[]
  for leaf, names in M.iter_leaves(root) do
    local name = M.full_name(names)
    local traces = traces_of[name]
    if not traces then
      traces = {}
      traces_of[name] = traces
      table.insert(order, name)
    end
    table.insert(traces, leaf.trace)
  end

  local shared = {}
  for _, name in ipairs(order) do
    local traces = traces_of[name]
    if #traces > 1 then
      table.insert(shared, { name = name, traces = traces })
    end
  end
  return shared
end

--- @type table<string, string> the characters that would carry a name onto a second line, and what a name spells each of them as instead
local LINE_BREAKS = {
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\v"] = "\\v",
  ["\f"] = "\\f",
}

--- @param names string[] describe/it name chain
--- @return string # the chain on one line, a break the source spelled a name over written as the escape it is, so that a listing keeps one line per test and every use of a name -- a --filter pattern, the schedule, an invariant_spec -- takes the one a report shows
function M.full_name(names)
  local joined = table.concat(
    vim.tbl_filter(function(s)
      return s ~= nil and s ~= ""
    end, names or {}),
    " "
  )
  return (joined:gsub("[\n\r\v\f]", LINE_BREAKS))
end

return M
