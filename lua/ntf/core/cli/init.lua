-- Controller logic, invoked by the `bin/ntf` launcher (a `nvim -l` script).
-- Parses args, discovers spec files, plans work items, runs them in parallel
-- worker processes, prints the report, and exits with the aggregate code.
local M = {}

--- @param root string ntf repository root (used to locate the worker script)
function M.run(root)
  local args = require("ntf.core.cli.args")

  local opts = args.parse(arg)
  if type(opts) == "string" then
    io.stderr:write(opts .. "\n")
    os.exit(2)
  end
  if opts.help then
    io.stdout:write(args.usage() .. "\n")
    os.exit(0)
  end

  require("ntf.core.runtime").setup()

  local ok, files = pcall(require("ntf.core.discover").specs, opts.paths)
  if not ok then
    io.stderr:write(tostring(files) .. "\n")
    os.exit(2)
  end
  if #files == 0 then
    io.stderr:write("no *_spec.lua found in: " .. table.concat(opts.paths, ", ") .. "\n")
    os.exit(2)
  end

  if opts.shuffle and not opts.seed then
    opts.seed = os.time()
  end

  local runner = require("ntf.core.runner")
  local items, load_errors = runner.plan(files, opts.isolate, opts.filter)

  local prog
  if not opts.no_progress then
    local total = 0
    for _, item in ipairs(items) do
      total = total + #item.node_ids
    end
    local color = vim.uv.guess_handle(2) == "tty" and not vim.env.NO_COLOR and opts.color ~= false
    prog = require("ntf.core.cli.progress").new({
      write = function(s)
        io.stderr:write(s)
        io.stderr:flush()
      end,
      color = color,
      total = total,
    })
  end

  local results = runner.run(items, {
    root = root,
    jobs = opts.jobs,
    shuffle = opts.shuffle,
    seed = opts.seed,
    on_item = prog and prog.on_item or nil,
  })
  if prog then
    prog.finish()
  end

  local text, code = require("ntf.core.report").build(results, load_errors, opts)
  io.stdout:write(text)
  os.exit(code)
end

return M
