local M = {}

--- @type table<string, { list: boolean?, mutation: boolean? }> what each command asks of the one pipeline below
local MODES = {
  ["run"] = {},
  ["list"] = { list = true },
  ["mutation.run"] = { mutation = true },
  ["mutation.list"] = { list = true, mutation = true },
  ["mutation.baseline.verify"] = { mutation = true },
}

--- @param opts NtfOptions
--- @param config NtfMutationConfig
--- @return integer exit_code
local function add_baseline(opts, config)
  local baseline = require("ntf.core.mutation.baseline")
  local report = require("ntf.core.controller.report")
  local mutant = assert(opts.mutation_mutant)
  local entry = baseline.build({
    path = mutant.path,
    row = mutant.row,
    col = mutant.col,
    operator = mutant.operator,
    replacement = opts.mutation_replacement,
    rationale = assert(opts.mutation_rationale),
    invariant_spec = opts.mutation_invariant_spec,
  }, vim.fn.getcwd())
  if type(entry) == "string" then
    io.stderr:write(entry .. "\n")
    return 2
  end

  local entries = baseline.insert(config.baseline, entry)
  if type(entries) == "string" then
    io.stderr:write(entries .. "\n")
    return 2
  end

  config.baseline = entries
  require("ntf.core.mutation.config").write(opts.mutation_config, config)
  io.stdout:write(
    ("added to %s: %s %s -> %s\n"):format(
      opts.mutation_config,
      report.locator(entry.path, { row = mutant.row, col = entry.col, operator = entry.operator }),
      report.oneline(entry.original),
      report.oneline(entry.replacement)
    )
  )
  return 0
end

--- @param opts NtfOptions
--- @param ctx { root: string, cwd: string, items: NtfWorkItem[], results: NtfResult[], baseline: NtfMutationBaselineEntry[]?, mutation_exclude: NtfMutationExcludeEntry[]?, mutation_operators: NtfMutationOperatorSelection?, unused_spec_excludes: NtfMutationExcludeEntry[]?, coverage_map: NtfMutationCoverageMap, coverage_excludes: string[], color: boolean }
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

  local started = vim.uv.hrtime()
  local summary = require("ntf.core.mutation").run(opts, {
    root = ctx.root,
    cwd = ctx.cwd,
    items = ctx.items,
    baseline_results = ctx.results,
    baseline = ctx.baseline,
    mutation_exclude = ctx.mutation_exclude,
    mutation_operators = ctx.mutation_operators,
    unused_spec_excludes = ctx.unused_spec_excludes,
    coverage_map = ctx.coverage_map,
    coverage_excludes = ctx.coverage_excludes,
    on_start = progress.on_start,
    on_task = progress.on_task,
  })
  progress.finish()

  if not opts.mutation_verify_baseline_only then
    require("ntf.core.mutation.results").write(opts.mutation_results, summary)
  end
  local elapsed = (vim.uv.hrtime() - started) * 1e-9
  io.stdout:write(
    "\n" .. require("ntf.core.mutation.report").summary(summary, ctx.cwd, { color = ctx.color, elapsed = elapsed })
  )

  local code = 0
  if #summary.lost > 0 then
    io.stdout:flush()
    io.stderr:write(
      ("mutation gate failed: %d baseline entr%s matched no mutant\n"):format(
        #summary.lost,
        #summary.lost == 1 and "y" or "ies"
      )
    )
    code = 1
  end
  if #summary.unused_excludes > 0 then
    io.stdout:flush()
    io.stderr:write(
      ("mutation gate failed: %d exclude entr%s covering nothing\n"):format(
        #summary.unused_excludes,
        #summary.unused_excludes == 1 and "y" or "ies"
      )
    )
    code = 1
  end
  if #summary.unused_spec_excludes > 0 then
    io.stdout:flush()
    io.stderr:write(
      ("mutation gate failed: %d exclude_spec entr%s covering nothing\n"):format(
        #summary.unused_spec_excludes,
        #summary.unused_spec_excludes == 1 and "y" or "ies"
      )
    )
    code = 1
  end
  if #summary.unpinned > 0 then
    io.stdout:flush()
    io.stderr:write(
      ("mutation gate failed: %d unpinned baseline entr%s\n"):format(
        #summary.unpinned,
        #summary.unpinned == 1 and "y" or "ies"
      )
    )
    code = 1
  end
  local killable = summary.counts.baseline_killable
  if killable > 0 then
    io.stdout:flush()
    io.stderr:write(
      ("mutation gate failed: %d baseline entr%s killable\n"):format(killable, killable == 1 and "y" or "ies")
    )
    code = 1
  end
  if opts.mutation_strict then
    local parts = {}
    for _, status in ipairs(require("ntf.core.controller.args").strict_categories) do
      if opts.mutation_strict[status] and summary.counts[status] > 0 then
        table.insert(parts, ("%d %s"):format(summary.counts[status], (status:gsub("_", " "))))
      end
    end
    if #parts > 0 then
      io.stdout:flush()
      io.stderr:write("mutation gate failed: " .. table.concat(parts, ", ") .. "\n")
      code = 1
    end
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
    io.stdout:write(args.usage(opts.command) .. "\n")
    os.exit(0)
  end
  local mode = MODES[opts.command]

  require("ntf.core.runtime").setup()

  local mutation_config --- @type NtfMutationConfig?
  if opts.mutation_config then
    local loaded = require("ntf.core.mutation.config").load(opts.mutation_config)
    if type(loaded) == "string" then
      io.stderr:write(loaded .. "\n")
      os.exit(2)
    end
    mutation_config = loaded
  end
  if opts.command == "mutation.baseline.add" then
    os.exit(add_baseline(opts, assert(mutation_config)))
  end

  local mutation_baseline = mutation_config and mutation_config.baseline
  local mutation_exclude = mutation_config and mutation_config.exclude
  local mutation_operators = mutation_config and mutation_config.operators
  local mutation_exclude_spec = mutation_config and mutation_config.exclude_spec or {}

  local ok, files = pcall(require("ntf.core.controller.discover").specs, opts.paths, opts.exclude_spec)
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

  --- @param code integer what the run has come to, before its teardown had a say
  local function finish(code)
    local teardown_err = teardown_error(global_hook.teardown)
    if teardown_err then
      io.stderr:write("--global-hook teardown error: " .. teardown_err .. "\n")
      code = code ~= 0 and code or 1
    end
    os.exit(code)
  end

  -- WHY: everything the run does after the global setup is inside this, so a
  -- raise anywhere in it -- a give-up budget spent, an output path that cannot
  -- be written -- still reaches the teardown that answers for the setup, and is
  -- reported by ntf rather than escaping as a bare `E5113: Lua chunk:`.
  -- NOT: catching around each step, which is a list that a later step is added
  -- outside of.
  --- @return integer # what the run has come to
  local function tested()
    local items, load_errors = require("ntf.core.controller.work").plan(files, opts.filter)

    -- WHY: a run that selected nothing is the same "nothing to run" the discovery
    -- above already exits 2 for, and a --filter that matches no test is how it
    -- happens by accident, where reporting 0 passed hands a green CI back for a
    -- typo.
    -- NOT: gating on the load errors too, which explain an empty selection
    -- themselves and already fail the run under their own report.
    if #items == 0 and #load_errors == 0 then
      if opts.filter then
        io.stderr:write("no test matched --filter: " .. opts.filter .. "\n")
      else
        io.stderr:write("no test declared in: " .. table.concat(opts.paths, ", ") .. "\n")
      end
      return 2
    end

    if mode.list and not mode.mutation then
      local list = require("ntf.core.controller.list")
      io.stdout:write(list.tests(items))
      io.stderr:write(list.load_errors(load_errors))

      return #load_errors > 0 and 1 or 0
    end
    local planned_items = items

    local schedule = require("ntf.core.controller.schedule")
    local schedule_cache_path = require("ntf.core.cache_path").schedule()
    items = schedule.order(items, schedule.load(schedule_cache_path), vim.fn.getcwd())

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
    local collector = require("ntf.core.coverage.collector")
    local coverage_excludes =
      vim.list_extend(collector.exclude_roots(files, cwd), collector.exclude_paths(opts.exclude_code))
    local exclude = require("ntf.core.mutation.exclude")
    local _, unused_spec_excludes = exclude.partition(files, mutation_exclude_spec, cwd)
    local coverage_map = require("ntf.core.mutation.coverage_map").new({
      ignore_items = exclude.item_indexes(items, mutation_exclude_spec, cwd),
    })

    local results, coverage, timing = require("ntf.core.controller.pool").run(items, {
      root = root,
      jobs = opts.jobs,
      timeout = opts.timeout,
      test_hook = opts.test_hook,
      coverage = opts.coverage or mode.mutation,
      coverage_excludes = coverage_excludes,
      on_item = prog and prog.on_item or nil,
      on_item_coverage = mode.mutation and coverage_map.add or nil,
      on_output = not mode.list and function(out)
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

    schedule.save(schedule_cache_path, results, cwd, opts.whole_suite)

    local text, code = report.build(results, load_errors, { color = color })
    if not mode.list then
      io.stdout:write(text)
      io.stdout:write("\n" .. report.timing(results, timing))
    end

    if opts.coverage then
      require("ntf.core.coverage.stats").write(opts.coverage_file, coverage)
      io.stdout:write("\n" .. require("ntf.core.coverage.report").summary(coverage, cwd))
    end

    if mode.mutation then
      if code ~= 0 then
        if mode.list then
          io.stdout:write(text)
        end
        io.stdout:flush()
        io.stderr:write(("mutation %s skipped: the tests must pass first\n"):format(mode.list and "list" or "run"))
        return code
      end
      if mode.list then
        local list = require("ntf.core.controller.list")
        local tests_text = list.tests(planned_items)
        local mutants_text = list.mutants(require("ntf.core.mutation").list(opts, {
          cwd = cwd,
          baseline = mutation_baseline,
          mutation_exclude = mutation_exclude,
          mutation_operators = mutation_operators,
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
          mutation_exclude = mutation_exclude,
          mutation_operators = mutation_operators,
          unused_spec_excludes = unused_spec_excludes,
          coverage_map = coverage_map,
          coverage_excludes = coverage_excludes,
          color = color,
        })
      end
    end

    return code
  end

  local ok_run, code = xpcall(tested, debug.traceback)
  if not ok_run then
    io.stdout:flush()
    io.stderr:write("ntf error: " .. tostring(code) .. "\n")
    code = 1
  end
  finish(code)
end

return M
