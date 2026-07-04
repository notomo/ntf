-- Builds the test tree from a spec file and owns the busted-compatible globals.
--
-- Building executes `describe` bodies (to discover nested `describe`/`it`) but
-- never runs `it` bodies. The same globals are reused at execution time; the
-- only execution-specific globals are `finally`, whose callbacks are collected
-- within a `collect_finallies` scope, and a runtime `pending()`, recognized by
-- not being inside a build (empty describe stack).

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

-- Sentinel carried by errors thrown to abort a running test as "pending".
M.PENDING = "__ntf_pending__"

-- build state: the stack of describe nodes, top = current (set during build)
local stack = {} ---@type NtfNode[]

-- receives `finally` callbacks while inside a collect_finallies scope
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
  -- `it` always requires a body; declaration-pending uses the explicit `pending`.
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
  -- declaration form when building; runtime-abort form while a test runs.
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

-- The busted-style test API. Exposed through `require("ntf")`; specs pull what
-- they need explicitly (`local describe, it = ntf.describe, ntf.it`) instead of
-- relying on injected globals.
-- `it` takes an optional opts table: `it(name, fn, { timeout = 1000 })`
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

--- Run `fn` with a fresh `finally` collector installed, restoring the
--- previous one afterwards (execute may nest inside a running test).
--- @param fn fun() must not throw; the caller catches errors inside
--- @return (fun())[] collected finally callbacks
function M.collect_finallies(fn)
  local saved = finally_collector
  finally_collector = {}
  fn()
  local collected = finally_collector
  finally_collector = saved
  return collected
end

--- A terminal unit of work: a test leaf (`it`/`pending`) or a `describe` whose
--- body errored during build. Such a describe is reported as an error in its own
--- right and is never descended into, since its children are unreliable.
--- @param node NtfNode
--- @return boolean
function M.is_leaf(node)
  return node.type == "it" or node.type == "pending" or node.load_error ~= nil
end

--- Build the test tree for a single spec file.
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
  -- A non-empty stack marks "building": declaration-form `pending(...)` is
  -- recorded as a node instead of aborting as a runtime pending. This holds
  -- even when a spec builds a tree while a test is running (ntf's own specs do).
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

--- Iterate the tree depth-first, yielding every terminal leaf in order.
--- @param root NtfNode
--- @return fun():NtfNode|nil
function M.iter_leaves(root)
  local result = {}
  local function walk(node)
    for _, child in ipairs(node.children or {}) do
      if M.is_leaf(child) then
        table.insert(result, child)
      else
        walk(child)
      end
    end
  end
  walk(root)
  local i = 0
  return function()
    i = i + 1
    return result[i]
  end
end

return M
