local M = {}

--- @param root string ntf repository root (used to locate the worker script)
function M.run(root)
  local args = require("ntf.core.controller.args")

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

  local ok, files = pcall(require("ntf.core.controller.discover").specs, opts.paths)
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

  local ok_setup, global_hook = xpcall(function()
    local hook = require("ntf.core.hook").load(opts.global_hook)
    hook.setup()
    return hook
  end, debug.traceback)
  if not ok_setup then
    io.stderr:write("--global-hook setup error: " .. tostring(global_hook) .. "\n")
    os.exit(1)
  end

  local items, load_errors = require("ntf.core.controller.work").plan(files, opts.filter)

  local prog
  if vim.uv.guess_handle(2) == "tty" then
    prog = require("ntf.core.controller.progress").new({
      write = function(s)
        io.stderr:write(s)
        io.stderr:flush()
      end,
      color = not vim.env.NO_COLOR,
    })
  end

  local report = require("ntf.core.controller.report")
  local color = report.resolve_color()

  local results, coverage = require("ntf.core.controller.pool").run(items, {
    root = root,
    jobs = opts.jobs,
    shuffle = opts.shuffle,
    seed = opts.seed,
    timeout = opts.timeout,
    test_hook = opts.test_hook,
    coverage = opts.coverage,
    on_item = prog and prog.on_item or nil,
    on_output = function(out)
      if prog then
        prog.newline()
      end
      io.stdout:write(report.output_block(out, color))
      io.stdout:flush()
    end,
  })
  if prog then
    prog.finish()
  end

  local teardown_err
  xpcall(global_hook.teardown, function(err)
    teardown_err = tostring(err) .. "\n" .. debug.traceback("", 2)
  end)

  local text, code = report.build(results, load_errors, { color = color, shuffle = opts.shuffle, seed = opts.seed })
  io.stdout:write(text)

  if opts.coverage then
    require("ntf.core.coverage.stats").write(opts.coverage_file, coverage)
    io.stdout:write("\n" .. require("ntf.core.coverage.report").summary(coverage, vim.fn.getcwd()))
  end

  if teardown_err then
    io.stderr:write("--global-hook teardown error: " .. teardown_err .. "\n")
    code = code ~= 0 and code or 1
  end

  os.exit(code)
end

return M
