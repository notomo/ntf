-- WHY: the worker runs via `-c "luafile <this>"`, after startup, which keeps the
-- vusted-compatible semantics.
-- NOT: `-l`, under which Neovim turns otherwise non-fatal Vim errors (E348 from
-- `expand()`, say) into hard errors, making many plugins behave differently than
-- they do under a normal session.

local protocol = require("ntf.core.worker.protocol")

local payload = protocol.payload()

require("ntf.core.worker.watchdog").start(payload.watchdog_ms)

local function main()
  local process_hook_error = require("ntf.core.runtime").setup(payload.process_hook)
  if process_hook_error then
    error(process_hook_error, 0)
  end

  local hook = require("ntf.core.hook").load("--test-hook", payload.test_hook)
  if type(hook) == "string" then
    error(hook, 0)
  end
  hook.setup()

  --- @return { message: string, traceback: string? }?
  local function teardown()
    local captured
    local ok = xpcall(hook.teardown, function(err)
      captured = { message = type(err) == "string" and err or vim.inspect(err), traceback = debug.traceback("", 2) }
    end)
    if ok then
      return nil
    end
    return captured
  end

  --- @param err { message: string, traceback: string? }
  local function teardown_result(err)
    return {
      id = "<teardown>",
      name = "teardown",
      names = { "teardown" },
      trace = { source = "@" .. payload.test_hook },
      status = "error",
      message = err.message,
      traceback = err.traceback,
    }
  end

  local applied
  if payload.mutation then
    applied = require("ntf.core.worker.mutate").install(payload.mutation, payload.cwd)
  end

  local collector
  if payload.coverage then
    collector = require("ntf.core.coverage.collector")
    collector.start({ cwd = payload.cwd, excludes = payload.coverage_excludes })
  end

  local tree = require("ntf.core.tree")
  local executor = require("ntf.core.worker.executor")

  -- WHY: a batch holds leaves of the same spec file next to each other, and its
  -- point is to pay that file's load once for all of them.
  -- NOT: building the tree per leaf, which puts the load back for every one.
  local roots = {}

  --- @param leaf NtfWorkerLeaf
  --- @return NtfResult[]? results, string? # why the file cannot answer for that leaf
  local function run_leaf(leaf)
    local root_node = roots[leaf.file]
    if not root_node then
      root_node = tree.build(leaf.file)
      roots[leaf.file] = root_node
    end
    local problem = root_node.load_error and tostring(root_node.load_error)
      or tree.divergence(root_node, leaf.node_id, leaf.names, leaf.leaves_count)
    if problem then
      return nil, problem
    end
    return executor.run(root_node, { [leaf.node_id] = true })
  end

  --- @param results NtfResult[]
  --- @return boolean # true once one of them is a result the run fails on
  local function detected(results)
    for _, result in ipairs(results) do
      if result.status == "failed" or result.status == "error" then
        return true
      end
    end
    return false
  end

  local results = {}
  local failed_index
  -- WHY: the payload carries the fields of a leaf itself, so a worker given no
  -- batch runs the one leaf it names through the same loop.
  -- NOT: a branch per shape, which leaves the single-leaf path to drift from
  -- the batched one it has to keep behaving like.
  for index, leaf in ipairs(payload.batch or { payload }) do
    local ran, problem = run_leaf(leaf)
    if problem then
      if collector then
        collector.stop()
      end
      local message = problem
      local teardown_err = teardown()
      if teardown_err then
        message = message .. "\n\nteardown error: " .. teardown_err.message
      end
      protocol.emit({ load_error = message, file = leaf.file }, payload.nonce)
      return 1
    end
    --- @cast ran NtfResult[]
    for _, result in ipairs(ran) do
      result.file = leaf.file
      table.insert(results, result)
    end
    if detected(ran) then
      failed_index = index
      break
    end
  end

  local coverage
  if collector then
    coverage = collector.stop()
  end
  local teardown_err = teardown()
  if teardown_err then
    table.insert(results, teardown_result(teardown_err))
  end
  local mutation_applied
  if applied then
    mutation_applied = applied()
  end
  protocol.emit({
    results = results,
    failed_index = failed_index,
    coverage = coverage,
    mutation_applied = mutation_applied,
  }, payload.nonce)

  if detected(results) then
    return 1
  end
  return 0
end

local ok, result = xpcall(main, debug.traceback)
if not ok then
  protocol.emit({ load_error = tostring(result), file = payload.file }, payload.nonce)
  os.exit(1)
end
os.exit(result)
