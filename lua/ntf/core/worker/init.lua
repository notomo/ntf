-- WHY: the worker runs via `-c "luafile <this>"`, after startup, which keeps the
-- vusted-compatible semantics.
-- NOT: `-l`, under which Neovim turns otherwise non-fatal Vim errors (E348 from
-- `expand()`, say) into hard errors, making many plugins behave differently than
-- they do under a normal session.

local protocol = require("ntf.core.worker.protocol")

-- WHY: the `xpcall(main, ...)` handler at the bottom reports `payload.file`, so
-- the payload has to exist even when `main` is what threw.
-- NOT: decoding it inside `main`.
local payload = protocol.payload()

local function main()
  require("ntf.core.runtime").setup()

  local hook = require("ntf.core.hook").load(payload.test_hook)
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
  local root_node = tree.build(payload.file)

  if root_node.load_error then
    -- WHY: a spec that failed to load has no meaningful coverage, and this path
    -- emits no results array, so a teardown error has to ride on the load-error
    -- message.
    -- NOT: emitting the coverage collected before the failure, and a
    -- `teardown_result` beside it as the normal path does.
    if collector then
      collector.stop()
    end
    local message = tostring(root_node.load_error)
    local teardown_err = teardown()
    if teardown_err then
      message = message .. "\n\nteardown error: " .. teardown_err.message
    end
    protocol.emit({ load_error = message, file = payload.file })
    return 1
  end

  local results = require("ntf.core.worker.executor").run(root_node, { [payload.node_id] = true })

  local coverage = collector and collector.stop() or nil
  local teardown_err = teardown()
  if teardown_err then
    table.insert(results, teardown_result(teardown_err))
  end
  local mutation_applied
  if applied then
    mutation_applied = applied()
  end
  protocol.emit({ results = results, coverage = coverage, mutation_applied = mutation_applied })

  for _, result in ipairs(results) do
    if result.status == "failed" or result.status == "error" then
      return 1
    end
  end
  return 0
end

local ok, result = xpcall(main, debug.traceback)
if not ok then
  protocol.emit({ load_error = tostring(result), file = payload.file })
  os.exit(1)
end
os.exit(result)
