local tree = require("ntf.core.tree")

local M = {}

--- @class NtfResult
--- @field id string leaf node id
--- @field name string? leaf node name
--- @field names string[] describe/it name chain
--- @field trace NtfTrace? declaration site
--- @field status "passed"|"failed"|"error"|"pending"
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

local function shuffled(list)
  local out = vim.list_extend({}, list)
  for i = #out, 2, -1 do
    local j = math.random(i)
    out[i], out[j] = out[j], out[i]
  end
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

local function run_hooks(hooks)
  for _, hook in ipairs(hooks) do
    local ok, err = xpcall(hook, handler)
    if not ok then
      return err
    end
  end
  return nil
end

--- @param root NtfNode tree root from ntf.core.tree
--- @param selected table<string,boolean>|nil set of leaf ids to run, nil = all
--- @param opts { shuffle?: boolean, seed?: integer }?
--- @return NtfResult[] results
function M.execute(root, selected, opts)
  opts = opts or {}
  local results = {}

  if opts.shuffle and opts.seed then
    math.randomseed(opts.seed)
  end

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

    -- The build-error message carries its own location, so no traceback is captured.
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
        status, message, traceback = "error", before_err.message, before_err.traceback
        return
      end
      local ok, err = xpcall(node.fn, handler)
      if not ok then
        if type(err) == "table" and err[tree.PENDING] then
          status, message = "pending", err.message
        else
          status, message, traceback = "failed", err.message, err.traceback
        end
      end
    end)
    for i = #finallies, 1, -1 do
      pcall(finallies[i])
    end

    local after_err = run_hooks(after_chain)
    if after_err and status == "passed" then
      status, message, traceback = "error", after_err.message, after_err.traceback
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

    local children = node.children or {}
    if opts.shuffle then
      children = shuffled(children)
    end

    for _, child in ipairs(children) do
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
