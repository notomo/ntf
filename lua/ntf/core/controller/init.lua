local M = {}

--- Runs the mutants and reports them, once the tests have passed.
--- @param opts NtfOptions
--- @param ctx { root: string, cwd: string, items: NtfWorkItem[], results: NtfResult[], baseline: NtfMutationBaselineEntry[]?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[], color: boolean }
--- @return integer exit_code
function M.mutate(opts, ctx)
  local progress = require("ntf.core.controller.progress").mutation({
    write = function(s)
      io.stderr:write(s)
      io.stderr:flush()
    end,
    enabled = vim.uv.guess_handle(2) == "tty",
    color = not vim.env.NO_COLOR,
  })

  local summary = require("ntf.core.mutation").run(opts, {
    root = ctx.root,
    cwd = ctx.cwd,
    items = ctx.items,
    baseline_results = ctx.results,
    baseline = ctx.baseline,
    coverage_map = ctx.coverage_map,
    coverage_excludes = ctx.coverage_excludes,
    on_start = progress.on_start,
    on_task = progress.on_task,
  })
  progress.finish()

  require("ntf.core.mutation.results").write(opts.mutation_results, summary)
  io.stdout:write("\n" .. require("ntf.core.mutation.report").summary(summary, ctx.cwd, { color = ctx.color }))

  local code = 0
  if #summary.lost > 0 then
    io.stdout:flush()
    io.stderr:write(
      ("%d --mutation-baseline entr%s matched no mutant\n"):format(#summary.lost, #summary.lost == 1 and "y" or "ies")
    )
    code = 1
  end
  if opts.mutation_threshold and summary.score and summary.score < opts.mutation_threshold then
    io.stdout:flush()
    io.stderr:write(
      ("mutation score %.1f%% is below the --mutation-threshold of %g%%\n"):format(
        summary.score,
        opts.mutation_threshold
      )
    )
    code = 1
  end
  return code
end

--- @param teardown fun()
--- @return string? # error message with traceback, nil on success
local function teardown_error(teardown)
  local err
  xpcall(teardown, function(e)
    err = tostring(e) .. "\n" .. debug.traceback("", 2)
  end)
  return err
end

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

  -- The baseline is loaded (and rejected) up front rather than in the mutation
  -- phase: a malformed file should fail like any other bad flag, not after the
  -- whole suite has run.
  local mutation_baseline --- @type NtfMutationBaselineEntry[]?
  if opts.mutation_baseline then
    local loaded = require("ntf.core.mutation.baseline").load(opts.mutation_baseline)
    if type(loaded) == "string" then
      io.stderr:write(loaded .. "\n")
      os.exit(2)
    end
    mutation_baseline = loaded
  end

  local ok, files = pcall(require("ntf.core.controller.discover").specs, opts.paths)
  if not ok then
    io.stderr:write(tostring(files) .. "\n")
    os.exit(2)
  end
  if #files == 0 then
    io.stderr:write("no *_spec.lua found in: " .. table.concat(opts.paths, ", ") .. "\n")
    os.exit(2)
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

  if opts.list and not opts.mutation then
    local list = require("ntf.core.controller.list")
    io.stdout:write(list.tests(items))
    io.stderr:write(list.load_errors(load_errors))

    local code = #load_errors > 0 and 1 or 0
    local list_teardown_err = teardown_error(global_hook.teardown)
    if list_teardown_err then
      io.stderr:write("--global-hook teardown error: " .. list_teardown_err .. "\n")
      code = code ~= 0 and code or 1
    end
    os.exit(code)
  end
  -- The listing keeps the declaration order even though the run below dispatches
  -- in schedule order: the reordering is a run-time optimization, and a stable
  -- listing is what grep/diff consumers need.
  local planned_items = items

  local schedule = require("ntf.core.controller.schedule")
  local schedule_cache_path = schedule.default_path()
  local schedule_cache = schedule.load(schedule_cache_path)
  items = schedule.order(items, schedule_cache, vim.fn.getcwd())

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

  local cwd = vim.fn.getcwd()
  -- The mutation run needs the same exclusion set as the coverage it is built on,
  -- so it is decided here rather than inside the pool.
  local collector = require("ntf.core.coverage.collector")
  local coverage_excludes =
    vim.list_extend(collector.exclude_roots(files, cwd), collector.exclude_paths(opts.exclude_code))
  local coverage_map = require("ntf.core.mutation.coverage_map").new()

  local results, coverage = require("ntf.core.controller.pool").run(items, {
    root = root,
    jobs = opts.jobs,
    timeout = opts.timeout,
    test_hook = opts.test_hook,
    coverage = opts.coverage or opts.mutation,
    coverage_excludes = coverage_excludes,
    on_item = prog and prog.on_item or nil,
    on_item_coverage = opts.mutation and coverage_map.add or nil,
    on_output = not opts.list and function(out)
      if prog then
        prog.newline()
      end
      io.stdout:write(report.output_block(out, color))
      io.stdout:flush()
    end or nil,
  })
  if prog then
    prog.finish()
  end

  schedule.save(schedule_cache_path, schedule_cache, results, cwd)

  local teardown_err = teardown_error(global_hook.teardown)

  local text, code = report.build(results, load_errors, { color = color })
  if not opts.list then
    io.stdout:write(text)
  end

  if opts.coverage and not opts.list then
    require("ntf.core.coverage.stats").write(opts.coverage_file, coverage)
    io.stdout:write("\n" .. require("ntf.core.coverage.report").summary(coverage, cwd))
  end

  if opts.mutation then
    -- A mutant is only meaningful against a suite that passes: against a failing
    -- one, every mutant would look detected.
    if code ~= 0 then
      if opts.list then
        io.stdout:write(text)
      end
      io.stdout:flush()
      io.stderr:write(("mutation %s skipped: the tests must pass first\n"):format(opts.list and "list" or "run"))
      os.exit(code)
    end
    if opts.list then
      local list = require("ntf.core.controller.list")
      local tests_text = list.tests(planned_items)
      local mutants_text = list.mutants(require("ntf.core.mutation").list(opts, {
        cwd = cwd,
        baseline = mutation_baseline,
        coverage_map = coverage_map,
        coverage_excludes = coverage_excludes,
      }))
      local separator = (#tests_text > 0 and #mutants_text > 0) and "\n" or ""
      io.stdout:write(tests_text .. separator .. mutants_text)
    else
      code = M.mutate(opts, {
        root = root,
        cwd = cwd,
        items = items,
        results = results,
        baseline = mutation_baseline,
        coverage_map = coverage_map,
        coverage_excludes = coverage_excludes,
        color = color,
      })
    end
  end

  if teardown_err then
    io.stderr:write("--global-hook teardown error: " .. teardown_err .. "\n")
    code = code ~= 0 and code or 1
  end

  os.exit(code)
end

return M
