-- Worker entry point. Launched by the controller as:
--   nvim --clean --headless -c "luafile <this>"
-- with parameters passed via environment variables.
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

local function main()
  local root = vim.env.NTF_ROOT
  vim.opt.runtimepath:prepend(root)

  require("ntf.core.runtime").setup()

  -- The `--setup` script (forwarded by the controller via NTF_SETUP) runs before
  -- any spec is built or executed, e.g. `require("lldebugger").start()` for
  -- stepping through tests. ntf itself has no debugger dependency; this is just an
  -- injection point. Errors here are caught by the xpcall around main() and
  -- surfaced as a load error.
  local setup = vim.env.NTF_SETUP
  if setup and setup ~= "" then
    dofile(setup)
  end

  local file = vim.env.NTF_FILE
  local nodes = vim.env.NTF_NODES
  local shuffle = vim.env.NTF_SHUFFLE == "1"
  local seed = tonumber(vim.env.NTF_SEED)

  local tree = require("ntf.core.tree")
  local root_node = tree.build(file)

  if root_node.load_error then
    emit({ load_error = tostring(root_node.load_error), file = file })
    return 1
  end

  local selected
  if nodes and nodes ~= "" and nodes ~= "all" then
    selected = {}
    for id in vim.gsplit(nodes, ",", { trimempty = true }) do
      selected[id] = true
    end
  end

  local results = require("ntf.core.run").execute(root_node, selected, {
    shuffle = shuffle,
    seed = seed,
  })

  emit({ results = results })

  for _, result in ipairs(results) do
    if result.status == "failed" or result.status == "error" then
      return 1
    end
  end
  return 0
end

local ok, result = xpcall(main, debug.traceback)
if not ok then
  emit({ load_error = tostring(result), file = vim.env.NTF_FILE })
  os.exit(1)
end
os.exit(result)
