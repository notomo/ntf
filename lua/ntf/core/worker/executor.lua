local tree = require("ntf.core.tree")

local M = {}

--- @alias NtfResultStatus "passed"|"failed"|"error"|"pending"

--- @class NtfResult
--- @field id string leaf node id
--- @field name string? leaf node name
--- @field names string[] describe/it name chain
--- @field trace NtfTrace? declaration site
--- @field status NtfResultStatus
--- @field message string? failure/error message
--- @field traceback string? captured traceback (failed/error)
--- @field duration number? wall time in seconds
--- @field file string? spec file path (set by the controller)

local function extend(a, b)
  local out = {}
  vim.list_extend(out, a)
  vim.list_extend(out, b)
  return out
end

local function append(list, value)
  local out = vim.list_extend({}, list)
  table.insert(out, value)
  return out
end

local function to_text(value)
  if value == nil or type(value) == "string" then
    return value
  end
  return vim.inspect(value)
end

local function handler(err)
  if type(err) == "table" and err[tree.PENDING] then
    return err
  end
  return { message = to_text(err), traceback = debug.traceback("", 2) }
end

local TOO_LATE_TO_PEND =
  "pending() once the result is decided: only a before_each or a test body leaves a test pending, since an after_each and a finally both run after the result"

--- @param err table what `handler` returned for a raise
--- @return boolean # true once the raise is the signal pending() sends from a running test
local function is_pending(err)
  return err[tree.PENDING] ~= nil
end

--- @param err table what `handler` returned for a raise a decided result leaves no room for
--- @return string? message
--- @return string? traceback
local function too_late(err)
  if is_pending(err) then
    return TOO_LATE_TO_PEND, nil
  end
  return err.message, err.traceback
end

--- @type table<string, true> the statuses that already fail the run, so a raise folded into one still reaches the exit code
local failing = { failed = true, error = true }

--- @param status NtfResultStatus what the body and the hooks before it decided
--- @param message string?
--- @param traceback string?
--- @param err table what `handler` returned for a raise from an after_each or a finally
--- @return NtfResultStatus
--- @return string?
--- @return string?
local function with_too_late(status, message, traceback, err)
  local late_message, late_traceback = too_late(err)
  if not failing[status] then
    return "error", late_message, late_traceback
  end
  return status,
    ("%s\nthen raised after the result was decided: %s"):format(message or "", late_message or ""),
    traceback
end

local function run_hooks(hooks)
  for _, hook in ipairs(hooks) do
    local ok, err = xpcall(hook, handler)
    if not ok then
      return err
    end
  end
  return nil
end

--- @param finallies (fun())[] in the order they were registered
--- @return { message: string?, traceback: string? }? # the first error raised, every callback having run whatever the one before it did
local function run_finallies(finallies)
  local first
  for i = #finallies, 1, -1 do
    local ok, err = xpcall(finallies[i], handler)
    if not ok then
      first = first or err
    end
  end
  return first
end

--- @param root NtfNode tree root from ntf.core.tree
--- @param selected table<string,boolean>|nil set of leaf ids to run, nil = all
--- @return NtfResult[] results
function M.run(root, selected)
  local results = {}

  local function has_selected(node)
    if tree.is_leaf(node) then
      return selected == nil or selected[node.id] == true
    end
    for _, child in ipairs(node.children or {}) do
      if has_selected(child) then
        return true
      end
    end
    return false
  end

  local function run_leaf(node, names, before_chain, after_chain)
    local result = {
      id = node.id,
      name = node.name,
      names = names,
      trace = node.trace,
    }

    if node.load_error then
      result.status = "error"
      result.message = to_text(node.load_error)
      table.insert(results, result)
      return
    end

    if node.type == "pending" then
      result.status = "pending"
      table.insert(results, result)
      return
    end

    local start = vim.uv.hrtime()
    local status, message, traceback = "passed", nil, nil

    local finallies = tree.collect_finallies(function()
      local before_err = run_hooks(before_chain)
      if before_err then
        if is_pending(before_err) then
          status, message = "pending", before_err.message
        else
          status, message, traceback = "error", before_err.message, before_err.traceback
        end
        return
      end
      local ok, err = xpcall(node.fn, handler)
      if not ok then
        if is_pending(err) then
          status, message = "pending", err.message
        else
          status, message, traceback = "failed", err.message, err.traceback
        end
      end
    end)
    local finally_err = run_finallies(finallies)
    if finally_err then
      status, message, traceback = with_too_late(status, message, traceback, finally_err)
    end

    local after_err = run_hooks(after_chain)
    if after_err then
      status, message, traceback = with_too_late(status, message, traceback, after_err)
    end

    result.status = status
    result.message = message
    result.traceback = traceback
    result.duration = (vim.uv.hrtime() - start) / 1e9
    table.insert(results, result)
  end

  local function descend(node, names, before_chain, after_chain)
    if not has_selected(node) then
      return
    end

    local child_before = extend(before_chain, node.before_each or {})
    local child_after = extend(node.after_each or {}, after_chain)

    for _, child in ipairs(node.children or {}) do
      local child_names = append(names, child.name)
      if child.type == "describe" and not child.load_error then
        descend(child, child_names, child_before, child_after)
      elseif selected == nil or selected[child.id] == true then
        run_leaf(child, child_names, child_before, child_after)
      end
    end
  end

  descend(root, {}, {}, {})
  return results
end

return M
