-- Controller logic, invoked by the `bin/ntf` launcher (a `nvim -l` script).
-- Parses args, discovers spec files, plans work items, runs them in parallel
-- worker processes, prints the report, and exits with the aggregate code.
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

  -- The `--global-hook` module returns an optional table with `setup`/`teardown`,
  -- like `--test-hook` — but it runs once in this launcher process, not per worker:
  -- `setup` before any spec is loaded (planning below loads the spec files),
  -- `teardown` after all workers have finished.
  local global_hook = {}
  if opts.global_hook then
    local ok_setup, err = xpcall(function()
      local loaded = dofile(opts.global_hook)
      if type(loaded) == "table" then
        global_hook = loaded
      end
      if global_hook.setup then
        global_hook.setup()
      end
    end, debug.traceback)
    if not ok_setup then
      io.stderr:write("--global-hook setup error: " .. tostring(err) .. "\n")
      os.exit(1)
    end
  end

  local runner = require("ntf.core.controller.dispatcher")
  local items, load_errors = runner.plan(files, opts.filter)

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
  -- Resolve once so the streamed OUTPUT blocks and the final report color alike.
  local color = report.resolve_color()

  local results, coverage = runner.run(items, {
    root = root,
    jobs = opts.jobs,
    shuffle = opts.shuffle,
    seed = opts.seed,
    timeout = opts.timeout,
    test_hook = opts.test_hook,
    coverage = opts.coverage,
    on_item = prog and prog.on_item or nil,
    -- Print each worker's captured output the instant it finishes, rather than
    -- holding it for the final report. Close any pending dot line first (on
    -- stderr) so the block starts on its own line instead of trailing the dots.
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

  -- Global teardown runs whatever the test outcome. Its error must not discard
  -- the results already produced, so capture it, still print the report, and
  -- only then fail the run.
  local teardown_err
  if global_hook.teardown then
    xpcall(global_hook.teardown, function(err)
      teardown_err = tostring(err) .. "\n" .. debug.traceback("", 2)
    end)
  end

  local text, code = report.build(results, load_errors, opts)
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
