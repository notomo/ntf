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

  local hook = require("ntf.core.hook").load(payload.test_hook)
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

  --- @param message string
  local function coverage_result(message)
    return {
      id = "<coverage>",
      name = "coverage",
      names = { "coverage" },
      trace = { source = "@" .. payload.file },
      status = "error",
      message = message,
    }
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
  local coverage_problem
  if payload.coverage then
    if debug.gethook() then
      coverage_problem =
        "coverage was not measured: the single debug.sethook slot was already taken when the test started, so measuring it would have silently disabled the hook that holds it"
    else
      collector = require("ntf.core.coverage.collector")
      collector.start({ cwd = payload.cwd, excludes = payload.coverage_excludes })
    end
  end

  local tree = require("ntf.core.tree")
  local root_node = tree.build(payload.file)

  local problem = root_node.load_error and tostring(root_node.load_error)
    or tree.divergence(root_node, payload.node_id, payload.names, payload.leaves_count)
  if problem then
    if collector then
      collector.stop()
    end
    local message = problem
    local teardown_err = teardown()
    if teardown_err then
      message = message .. "\n\nteardown error: " .. teardown_err.message
    end
    protocol.emit({ load_error = message, file = payload.file }, payload.nonce)
    return 1
  end

  local results = require("ntf.core.worker.executor").run(root_node, { [payload.node_id] = true })

  local coverage
  if collector then
    coverage, coverage_problem = collector.stop()
  end
  if coverage_problem then
    table.insert(results, coverage_result(coverage_problem))
  end
  local teardown_err = teardown()
  if teardown_err then
    table.insert(results, teardown_result(teardown_err))
  end
  local mutation_applied
  if applied then
    mutation_applied = applied()
  end
  protocol.emit({ results = results, coverage = coverage, mutation_applied = mutation_applied }, payload.nonce)

  for _, result in ipairs(results) do
    if result.status == "failed" or result.status == "error" then
      return 1
    end
  end
  return 0
end

local ok, result = xpcall(main, debug.traceback)
if not ok then
  protocol.emit({ load_error = tostring(result), file = payload.file }, payload.nonce)
  os.exit(1)
end
os.exit(result)
