local mutate = require("ntf.core.worker.mutate")
local protocol = require("ntf.core.worker.protocol")

local M = {}

-- WHY: a trial can replace the module system itself -- ntf's own coverage
-- collector installs a loader and its own loadfile, and a mutant that breaks
-- their teardown leaves them installed -- and a loader ahead of the mutation one
-- serves the next mutant's module unmutated, which reads as a mutant no test
-- reached rather than as the trial that broke it.
-- NOT: dropping what was loaded and leaving the loaders as they are, which
-- carries one mutant's leak into the verdict of every mutant after it.
--- @return fun() # puts the module system back the way it is now, so what one mutant's trials loaded or replaced never reaches the next
function M.reset_point()
  local loaded = {}
  for name, module in pairs(package.loaded) do
    loaded[name] = module
  end
  local loaders = vim.list_slice(package.loaders)
  local previous = { loadfile = _G.loadfile, dofile = _G.dofile }

  return function()
    for name in pairs(package.loaded) do
      package.loaded[name] = nil
    end
    for name, module in pairs(loaded) do
      package.loaded[name] = module
    end
    package.loaders = vim.list_slice(loaders)
    _G.loadfile = previous.loadfile
    _G.dofile = previous.dofile
  end
end

--- @param engine { tree: table, executor: table } the copy of the engine this mutant is taken with
--- @param roots table<string, NtfNode> the trees built for the mutant being taken
--- @param leaf NtfWorkerLeaf
--- @return NtfResult[]
local function run_leaf(engine, roots, leaf)
  local tree = engine.tree
  local root_node = roots[leaf.file]
  if not root_node then
    root_node = tree.build(leaf.file)
    roots[leaf.file] = root_node
  end
  local problem = root_node.load_error and tostring(root_node.load_error)
    or tree.divergence(root_node, leaf.node_id, leaf.names, leaf.leaves_count)
  if problem then
    return { { id = leaf.node_id, names = leaf.names, status = "error", message = problem } }
  end
  return engine.executor.run(root_node, { [leaf.node_id] = true })
end

--- @param tree table the copy of ntf.core.tree this mutant is taken with
--- @param results NtfResult[]
--- @return string? # full name of the first test that came back failed or errored
local function detected_by(tree, results)
  for _, result in ipairs(results) do
    if result.status == "failed" or result.status == "error" then
      return tree.full_name(result.names or {})
    end
  end
  return nil
end

--- @param engine { tree: table, executor: table } the copy of the engine this mutant is taken with
--- @param hook NtfHook
--- @param roots table<string, NtfNode>
--- @param leaf NtfWorkerLeaf
--- @return string? # full name of what failed, nil once the leaf and the hooks bracketing it all passed
local function attempt(engine, hook, roots, leaf)
  if not pcall(hook.setup) then
    return engine.tree.full_name(leaf.names)
  end
  local failed = detected_by(engine.tree, run_leaf(engine, roots, leaf))
  if not pcall(hook.teardown) then
    return failed or "teardown"
  end
  return failed
end

--- @param payload NtfWorkerPayload
--- @param hook NtfHook run around every trial, as it is around the one test of a worker given a leaf
function M.run(payload, hook)
  local reset = M.reset_point()
  for _, job in ipairs(payload.mutants or {}) do
    reset()
    local applied, uninstall = mutate.install(job.mutation, payload.cwd)
    -- WHY: ntf runs its own specs, so the engine a mutant is of is the one that
    -- runs it. Loading it after the mutation gives the spec and the worker the
    -- same copy, where loading it before gives them two, whose module-level
    -- state -- the stack ntf.core.tree builds into -- no longer answers for the
    -- other, and every mutant of the engine reads as one every test detects.
    -- NOT: requiring them at the top of this file, as the modules ntf.core.tree
    -- itself cannot be a mutant of are.
    local engine = { tree = require("ntf.core.tree"), executor = require("ntf.core.worker.executor") }
    local roots = {}

    local status, killed_by
    local retried = {}
    for trial_index, trial in ipairs(job.trials) do
      protocol.emit_event({ type = "begin", index = job.index, trial = trial_index }, payload.nonce)
      local failed = attempt(engine, hook, roots, trial)
      -- WHY: a trial that failed before anything loaded the mutated source
      -- failed at something the mutant never reached, and the run has as many
      -- of those as the suite has tests that fail on their own.
      -- NOT: taking any failure, which reads a broken test as a detection of
      -- every mutant it happens to be a trial of.
      if failed and applied() then
        -- WHY: the trials of one mutant share this process, so a test failing
        -- on what an earlier one left behind reads exactly like a detection,
        -- and a test that detects the mutant detects it however often it runs.
        -- NOT: taking the first failure, which makes the tests that ran before
        -- it part of the evidence.
        protocol.emit_event({ type = "begin", index = job.index, trial = trial_index }, payload.nonce)
        if attempt(engine, hook, roots, trial) then
          status, killed_by = "killed", failed
          break
        end
        table.insert(retried, failed)
      end
    end

    uninstall()
    if not status then
      status = applied() and "survived" or "not_applied"
    end
    protocol.emit_event({
      type = "verdict",
      index = job.index,
      status = status,
      killed_by = killed_by,
      retried = #retried > 0 and retried or nil,
    }, payload.nonce)
  end
end

return M
