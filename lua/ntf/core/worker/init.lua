-- The worker runs via `-c "luafile <this>"` (after startup) rather than `-l` on
-- purpose: under `-l` Neovim turns otherwise non-fatal Vim errors (e.g. E348 from
-- `expand()`) into hard errors, which would make many plugins behave differently
-- than they do under a normal session. `-c` keeps the vusted-compatible semantics.

local function emit(payload)
  io.stdout:write("\n<<<NTF_JSON>>>\n")
  io.stdout:write(vim.json.encode(payload))
  io.stdout:write("\n<<<END_NTF_JSON>>>\n")
end

-- Decoded at module scope so the error handler below can still attribute a
-- failure to its spec file.
local payload = vim.json.decode(vim.env._NTF_WORKER_PAYLOAD)

local function main()
  vim.opt.runtimepath:prepend(payload.root)

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

  local collector
  if payload.coverage then
    collector = require("ntf.core.coverage.collector")
    collector.start({ cwd = payload.cwd, excludes = payload.coverage_excludes })
  end

  local tree = require("ntf.core.tree")
  local root_node = tree.build(payload.file)

  if root_node.load_error then
    -- A spec that failed to load has no meaningful coverage; drop the hook and
    -- report only the load error (with any teardown error appended, since this path
    -- has no results array to carry it).
    if collector then
      collector.stop()
    end
    local message = tostring(root_node.load_error)
    local teardown_err = teardown()
    if teardown_err then
      message = message .. "\n\nteardown error: " .. teardown_err.message
    end
    emit({ load_error = message, file = payload.file })
    return 1
  end

  local selected
  if payload.node_ids and #payload.node_ids > 0 then
    selected = {}
    for _, id in ipairs(payload.node_ids) do
      selected[id] = true
    end
  end

  local results = require("ntf.core.worker.executor").execute(root_node, selected, {
    shuffle = payload.shuffle,
    seed = payload.seed,
  })

  local coverage = collector and collector.stop() or nil
  local teardown_err = teardown()
  if teardown_err then
    table.insert(results, teardown_result(teardown_err))
  end
  if coverage then
    emit({ results = results, coverage = coverage })
  else
    emit({ results = results })
  end

  for _, result in ipairs(results) do
    if result.status == "failed" or result.status == "error" then
      return 1
    end
  end
  return 0
end

local ok, result = xpcall(main, debug.traceback)
if not ok then
  emit({ load_error = tostring(result), file = payload.file })
  os.exit(1)
end
os.exit(result)
