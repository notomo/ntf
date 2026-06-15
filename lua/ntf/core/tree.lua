-- Builds the test tree from a spec file and owns the busted-compatible globals.
--
-- Building executes `describe` bodies (to discover nested `describe`/`it`) but
-- never runs `it` bodies. The same globals are reused at execution time; the
-- only execution-specific globals are `finally` and a runtime `pending()`, which
-- are routed through the mutable hooks installed by `ntf.core.run`.
local builder = require("ntf.assert.builder")

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
--- @field setups (fun())[]? setup hooks (root/describe only)
--- @field teardowns (fun())[]? teardown hooks (root/describe only)
--- @field isolate boolean? run this subtree in its own process (describe/it)
--- @field trace NtfTrace? declaration site
--- @field fn fun()? test body (it only)
--- @field output "always"|"never"? captured-output handling (it only)
--- @field load_error any? load/build error captured on this node (root/describe)

-- Sentinel carried by errors thrown to abort a running test as "pending".
M.PENDING = "__ntf_pending__"

-- build state: the stack of describe nodes, top = current (set during build)
local stack = {} ---@type NtfNode[]

-- execution hooks (set by ntf.core.run while a test body is running)
local finally_collector = nil
local executing = false

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
--- @param opts NtfDescribeOption?
--- @return NtfNode node
local function new_describe(name, fn, opts)
  local node = {
    type = "describe",
    name = name,
    id = nil,
    children = {},
    before_each = {},
    after_each = {},
    setups = {},
    teardowns = {},
    isolate = opts and opts.isolate or false,
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
    isolate = opts and opts.isolate or false,
    -- "always" (default) surfaces captured output in the report; "never" drops it.
    output = opts and opts.output or "always",
  }
  return add_child(node)
end

--- @param name string
--- @param fn fun()? optional body (ignored; pending is never executed)
--- @return NtfNode node
local function new_pending(name, fn)
  -- declaration form when building; runtime-abort form while a test runs.
  if executing then
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
-- describe / it take an optional opts table: `describe(name, fn, { isolate = true })`
M.describe = new_describe
M.it = new_it
M.pending = new_pending
M.before_each = add_hook("before_each")
M.after_each = add_hook("after_each")
M.setup = add_hook("setups")
M.teardown = add_hook("teardowns")
M.finally = function(fn)
  if finally_collector then
    table.insert(finally_collector, fn)
  end
end
M.assert = builder.assert

--- @param collector (fun())[]|nil list to receive finally callbacks, or nil to disable
function M.set_finally_collector(collector)
  finally_collector = collector
end

--- @param value boolean whether a test body is currently running
function M.set_executing(value)
  executing = value
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
    setups = {},
    teardowns = {},
  }
  stack = { root }

  -- A spec may itself build a tree while a test is running (ntf's own specs do).
  -- Force `executing` off during the build so declaration-form `pending(...)` is
  -- recorded as a node instead of aborting as a runtime pending, then restore.
  local was_executing = executing
  executing = false

  local chunk, load_err = loadfile(file_path)
  if not chunk then
    root.load_error = load_err
    executing = was_executing
    return root
  end

  local ok, err = pcall(chunk)
  if not ok then
    root.load_error = err
  end
  stack = {}
  executing = was_executing
  return root
end

--- Iterate the tree depth-first, yielding every `it`/`pending` leaf in order.
--- @param root NtfNode
--- @return fun():NtfNode|nil
function M.iter_leaves(root)
  local result = {}
  local function walk(node)
    for _, child in ipairs(node.children or {}) do
      if child.type == "it" or child.type == "pending" then
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
