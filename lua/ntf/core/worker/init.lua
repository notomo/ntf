-- Worker entry point. Launched by the controller as:
--   nvim --clean --headless -c "luafile <this>"
-- with all parameters passed as one internal JSON env var, _NTF_WORKER_PAYLOAD.
--
-- It is run with `-c` (after startup) rather than `-l` on purpose: under `-l`
-- Neovim turns otherwise non-fatal Vim errors (e.g. E348 from `expand()`) into
-- hard errors, which would make many plugins behave differently than they do
-- under a normal session. `-c` keeps the vusted-compatible semantics.
--
-- Builds the spec file's tree, runs the requested leaf ids, and emits a JSON
-- result document delimited by markers (so stray output cannot corrupt it).
local function emit(payload)
  io.stdout:write("\n<<<NTF_JSON>>>\n")
  io.stdout:write(vim.json.encode(payload))
  io.stdout:write("\n<<<END_NTF_JSON>>>\n")
end

-- All worker parameters arrive as one internal JSON env var set by the controller
-- (see runner.lua). Decoded at module scope so the error handler below can still
-- attribute a failure to its spec file.
local payload = vim.json.decode(vim.env._NTF_WORKER_PAYLOAD)

local function main()
  vim.opt.runtimepath:prepend(payload.root)

  require("ntf.core.runtime").setup()

  -- The `--setup` script runs before any spec is built or executed, e.g.
  -- `require("lldebugger").start()` for stepping through tests. ntf itself has no
  -- debugger dependency; this is just an injection point. Errors here are caught
  -- by the xpcall around main() and surfaced as a load error.
  if payload.setup and payload.setup ~= "" then
    dofile(payload.setup)
  end

  local tree = require("ntf.core.tree")
  local root_node = tree.build(payload.file)

  if root_node.load_error then
    emit({ load_error = tostring(root_node.load_error), file = payload.file })
    return 1
  end

  local selected
  if payload.node_ids and #payload.node_ids > 0 then
    selected = {}
    for _, id in ipairs(payload.node_ids) do
      selected[id] = true
    end
  end

  -- Coverage is collected only for the test execution below: the line hook is
  -- installed right before and removed right after, so building the tree and
  -- ntf's own machinery are not counted.
  local collector
  if payload.coverage then
    collector = require("ntf.core.coverage.collector")
    collector.start({ cwd = payload.cwd })
  end

  local results = require("ntf.core.worker.executor").execute(root_node, selected, {
    shuffle = payload.shuffle,
    seed = payload.seed,
  })

  if collector then
    emit({ results = results, coverage = collector.stop() })
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
