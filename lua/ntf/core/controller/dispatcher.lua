local tree = require("ntf.core.tree")

local M = {}

--- @class NtfLoadError
--- @field file string spec file path
--- @field message string error message

--- @class NtfLeafInfo
--- @field names string[] describe/it name chain
--- @field trace NtfTrace? declaration site
--- @field type "it"|"pending"|"describe"

--- @class NtfWorkItem
--- @field file string spec file path
--- @field node_ids string[] leaf ids to run in one worker
--- @field map table<string, NtfLeafInfo> leaf id -> leaf info (whole file)
--- @field timeout integer? per-item timeout in ms from the isolation-unit node

local BEGIN = "<<<NTF_JSON>>>"
local END = "<<<END_NTF_JSON>>>"

local function full_name(names)
  return table.concat(
    vim.tbl_filter(function(s)
      return s ~= nil and s ~= ""
    end, names or {}),
    " "
  )
end

local function item_scope(item)
  local prefix
  for _, id in ipairs(item.node_ids) do
    local names = (item.map[id] or {}).names or {}
    if not prefix then
      prefix = names
    else
      local n = 0
      for i = 1, math.min(#prefix, #names) do
        if prefix[i] == names[i] then
          n = i
        else
          break
        end
      end
      prefix = vim.list_slice(prefix, 1, n)
    end
  end
  return full_name(prefix)
end

--- @return table<string, NtfLeafInfo>
local function leaf_map(root)
  local map = {}
  local function walk(node, names)
    for _, child in ipairs(node.children or {}) do
      local child_names = vim.list_extend(vim.list_extend({}, names), { child.name })
      if tree.is_leaf(child) then
        map[child.id] = { names = child_names, trace = child.trace, type = child.type }
      else
        walk(child, child_names)
      end
    end
  end
  walk(root, {})
  return map
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
      local map = leaf_map(root)
      for leaf in tree.iter_leaves(root) do
        if not filter or full_name(map[leaf.id].names):find(filter) ~= nil then
          table.insert(items, { file = file, node_ids = { leaf.id }, map = map, timeout = leaf.timeout })
        end
      end
    end
  end

  return items, load_errors
end

local function parse_output(stdout)
  if not stdout then
    return nil
  end
  local from = stdout:find(BEGIN, 1, true)
  local to = stdout:find(END, 1, true)
  if not from or not to then
    return nil
  end
  local json = stdout:sub(from + #BEGIN, to - 1)
  local ok, decoded = pcall(vim.json.decode, json)
  if not ok then
    return nil
  end
  return decoded
end

-- A worker's captured output is everything it wrote to either standard stream.
-- On stdout that means explicit `io.write`/`io.stdout:write`/native writes (the
-- result marker block is excluded; `emit` is always the last thing written). On
-- stderr it means `print`, `vim.api.nvim_echo` and other messages, which Neovim
-- routes to its message channel rather than stdout. The two streams cannot be
-- interleaved after the fact, so stdout is shown first, then stderr.
local function worker_output(stdout, stderr)
  local from = stdout and stdout:find(BEGIN, 1, true)
  local out = stdout and (from and stdout:sub(1, from - 1) or stdout) or ""
  local parts = {}
  for _, blob in ipairs({ out, stderr or "" }) do
    blob = blob:gsub("\n$", "")
    if blob ~= "" then
      table.insert(parts, blob)
    end
  end
  return table.concat(parts, "\n")
end

--- @param timed_out_ms integer? the timeout the worker was killed for exceeding
local function results_of(item, obj, timed_out_ms)
  local decoded = parse_output(obj.stdout)

  if decoded and decoded.results then
    for _, result in ipairs(decoded.results) do
      result.file = item.file
    end
    return decoded.results
  end

  local detail
  if timed_out_ms then
    detail = ("worker timed out after %dms"):format(timed_out_ms)
  else
    detail = (obj.stderr ~= "" and obj.stderr)
      or (decoded and decoded.load_error)
      or ("worker exited with code " .. tostring(obj.code))
  end
  local results = {}
  for _, id in ipairs(item.node_ids) do
    local info = item.map[id] or { names = { "?" } }
    table.insert(results, {
      file = item.file,
      id = id,
      names = info.names,
      trace = info.trace,
      status = "error",
      message = detail,
    })
  end
  return results
end

--- @class NtfWorkerOutput
--- @field file string spec file path
--- @field name string the test scope the worker covered (its full describe/it name)
--- @field output string captured stdout blob

--- Captured output is handed to `on_output` the moment each worker finishes; the
--- cost is that blocks appear in worker-completion order, not deterministic spec order.
--- @param items NtfWorkItem[]
--- @param opts { root: string, jobs?: integer, shuffle?: boolean, seed?: integer, timeout?: integer, test_hook?: string, coverage?: boolean, on_item?: fun(item: NtfWorkItem, results: NtfResult[]), on_output?: fun(out: NtfWorkerOutput) }
--- @return NtfResult[] results, table coverage merged per-file line hit counts
function M.run(items, opts)
  local worker = vim.fs.joinpath(opts.root, "lua/ntf/core/worker/init.lua")
  local cwd = vim.fn.getcwd()
  local jobs = opts.jobs or (vim.uv.available_parallelism and vim.uv.available_parallelism()) or 4
  local total = #items

  local results = {}
  local coverage = require("ntf.core.coverage.collector")
  local merged_coverage = {}
  local coverage_excludes
  if opts.coverage then
    local spec_files = vim.tbl_map(function(item)
      return item.file
    end, items)
    coverage_excludes = coverage.exclude_roots(spec_files, cwd)
  end
  local started = 0
  local finished = 0
  local fatal

  local function spawn_next()
    if started >= total then
      return
    end
    started = started + 1
    local item = items[started]

    local timeout = item.timeout or opts.timeout
    if timeout == 0 then
      timeout = nil
    end

    -- Launch via `-c "luafile"` (after startup) instead of `-l`: see worker/init.lua.
    -- Parameters go through the environment since `arg` is not populated for -c.
    local cmd = {
      vim.v.progpath,
      "--clean",
      "--headless",
      -- Workers run in parallel in the same cwd, where the swap file name for an
      -- unnamed buffer is shared, so concurrent workers collide on it (E303).
      -- Tests do not need swap files; disable before the first buffer is created.
      "--cmd",
      "set noswapfile",
      "-c",
      "luafile " .. worker,
    }
    local env = {
      _NTF_WORKER_PAYLOAD = vim.json.encode({
        root = opts.root,
        file = item.file,
        node_ids = item.node_ids,
        shuffle = opts.shuffle or false,
        seed = opts.seed,
        test_hook = opts.test_hook,
        coverage = opts.coverage or false,
        coverage_excludes = coverage_excludes,
        cwd = cwd,
      }),
    }

    -- We enforce the timeout ourselves with SIGKILL rather than vim.system's
    -- `timeout` option, which sends SIGTERM. A worker spinning in pure Lua never
    -- reaches Neovim's event loop to handle SIGTERM, so only SIGKILL is guaranteed
    -- to stop a hung test.
    local timed_out = false
    local timer
    local proc = vim.system(cmd, { cwd = cwd, env = env, text = true }, function(obj)
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
      -- libuv would just log and drop an error raised here; capture the first
      -- to re-raise after the wait.
      local ok, err = xpcall(function()
        local item_results = results_of(item, obj, timed_out and timeout or nil)
        vim.list_extend(results, item_results)
        if opts.coverage then
          local decoded = parse_output(obj.stdout)
          coverage.merge(merged_coverage, decoded and decoded.coverage)
        end
        if opts.on_output and parse_output(obj.stdout) then
          local blob = worker_output(obj.stdout, obj.stderr)
          if blob ~= "" then
            opts.on_output({ file = item.file, name = item_scope(item), output = blob })
          end
        end
        if opts.on_item then
          opts.on_item(item, item_results)
        end
      end, debug.traceback)
      if not ok then
        fatal = fatal or err
      end
      finished = finished + 1
      vim.schedule(spawn_next)
    end)
    if timeout then
      timer = vim.uv.new_timer()
      if timer then
        timer:start(timeout, 0, function()
          timed_out = true
          pcall(function()
            proc:kill(9)
          end)
        end)
      end
    end
  end

  for _ = 1, math.min(jobs, total) do
    spawn_next()
  end

  vim.wait(10 * 60 * 1000, function()
    return finished >= total or fatal ~= nil
  end, 20)

  if fatal then
    error(fatal, 0)
  end

  if opts.coverage then
    for _, path in ipairs(coverage.measurable_files(cwd, coverage_excludes)) do
      if not merged_coverage[path] then
        merged_coverage[path] = { max = 0, lines = {} }
      end
    end
  end

  return results, merged_coverage
end

return M
