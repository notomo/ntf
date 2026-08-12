local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local mutate = require("ntf.core.worker.mutate")
local operators = require("ntf.core.mutation.operators")
local driver = require("ntf.core.worker.driver")
local work = require("ntf.core.controller.work")
local helper = require("ntf.test.helper")

describe("ntf.core.worker.mutate.module_names", function()
  it("maps a runtimepath module path to its require name", function()
    assert.same({ ["a.b"] = true }, mutate.module_names("/root/lua/a/b.lua", "/root"))
  end)

  it("maps an init module to both of its require names", function()
    assert.same({ ["a"] = true, ["a.init"] = true }, mutate.module_names("/root/lua/a/init.lua", "/root"))
  end)

  it("also maps the package.path layout without the lua directory", function()
    assert.same({ ["a.b"] = true }, mutate.module_names("/root/a/b.lua", "/root"))
  end)

  it("maps nothing outside the working directory", function()
    assert.same({}, mutate.module_names("/other/lua/a/b.lua", "/root"))
  end)

  it("maps nothing for a non-Lua file under the working directory", function()
    assert.same({}, mutate.module_names("/root/notes.txt", "/root"))
  end)
end)

local function first_mutation(path, operator)
  local file = assert(io.open(path, "r"))
  local src = file:read("*a")
  file:close()

  for _, site in ipairs(operators.enumerate(src)) do
    if site.operator == operator then
      return {
        path = vim.fs.normalize(path),
        start_byte = site.start_byte,
        end_byte = site.end_byte,
        original = site.original,
        replacement = site.replacement,
      }
    end
  end
  error(("no %s site in %s"):format(operator, path))
end

local function launch(item, mutation, cwd, test_hook)
  local done
  driver.launch(
    item,
    { root = helper.root, cwd = cwd, timeout = 30000, mutation = mutation, test_hook = test_hook },
    function(outcome)
      done = outcome
    end
  )
  vim.wait(30000, function()
    return done ~= nil
  end, 20)
  return assert(done, "the worker did not finish")
end

local SPEC = [[
local ntf = require("ntf")
ntf.describe("is_positive", function()
  ntf.it("is false at the boundary", function()
    ntf.assert.is_false(require("mod").is_positive(0))
  end)
end)
]]

describe("ntf.core.worker.mutate.install", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("mutates the module the spec requires, so a covering test detects it", function()
    local cwd = helper.test_data.full_path
    local module = helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    local item = work.plan({ helper.test_data:create_file("spec/mod_spec.lua", SPEC) })[1]

    local outcome = launch(item, first_mutation(module, "swap-relational"), cwd)

    assert.is_true(outcome.mutation_applied)
    assert.equal("failed", outcome.results[1].status)
  end)

  it("mutates a module that was already loaded before the spec ran", function()
    local cwd = helper.test_data.full_path
    local module = helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    local hook_that_leaves_the_module_in_package_loaded = helper.test_data:create_file(
      "hook.lua",
      [[
require("mod")
return {}
]]
    )
    local item = work.plan({ helper.test_data:create_file("spec/mod_spec.lua", SPEC) })[1]

    local outcome =
      launch(item, first_mutation(module, "swap-relational"), cwd, hook_that_leaves_the_module_in_package_loaded)

    assert.is_true(outcome.mutation_applied)
    assert.equal("failed", outcome.results[1].status)
  end)

  it("loads the mutated source ahead of the runtimepath loader", function()
    local cwd = helper.test_data.full_path
    local module = helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    local original_loaders = {}
    for _, loader in ipairs(package.loaders) do
      original_loaders[loader] = true
    end
    -- WHY: with cwd on the runtimepath Neovim's own loader resolves the module
    -- too, so the installed index below has to win against it.
    -- NOT: leaving cwd off the runtimepath, where any install position passes.
    vim.opt.runtimepath:append(cwd)

    local applied = mutate.install(first_mutation(module, "swap-relational"), cwd)
    local installed_index
    for i, loader in ipairs(package.loaders) do
      if not original_loaders[loader] then
        installed_index = i
      end
    end
    local applied_before = applied()
    local ok, mod = pcall(require, "mod")
    local applied_after = applied()

    package.loaded["mod"] = nil
    vim.opt.runtimepath:remove(cwd)
    for i = #package.loaders, 1, -1 do
      if not original_loaders[package.loaders[i]] then
        table.remove(package.loaders, i)
      end
    end

    assert(ok, mod)
    -- WHY: a mutation trial's worker already has its own mutation loader
    -- installed, which would mask a one-slot shift.
    -- NOT: letting a require of a runtimepath-resolvable module stand in for the
    -- index.
    local just_after_the_preload_loader = 2
    assert.equal(just_after_the_preload_loader, installed_index)
    assert.is_false(applied_before)
    assert.is_true(applied_after)

    local only_the_mutated_source_is_positive_at_zero = mod.is_positive(0)
    assert.is_true(only_the_mutated_source_is_positive_at_zero)
  end)

  it("closes the file it read the mutated source from", function()
    local cwd = helper.test_data.full_path
    local module = helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    local original_loaders = {}
    for _, loader in ipairs(package.loaders) do
      original_loaders[loader] = true
    end
    local mutation = first_mutation(module, "swap-relational")
    mutate.install(mutation, cwd)
    finally(function()
      package.loaded["mod"] = nil
      for i = #package.loaders, 1, -1 do
        if not original_loaders[package.loaders[i]] then
          table.remove(package.loaders, i)
        end
      end
    end)

    assert.is_false(helper.leaves_file_open(mutation.path, function()
      require("mod")
    end))
  end)

  it("names the mutated chunk after the original path, so tracebacks stay attributable to it", function()
    local cwd = helper.test_data.full_path
    local module = helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    local original_loaders = {}
    for _, loader in ipairs(package.loaders) do
      original_loaders[loader] = true
    end

    mutate.install(first_mutation(module, "swap-relational"), cwd)
    local ok, mod = pcall(require, "mod")

    package.loaded["mod"] = nil
    for i = #package.loaders, 1, -1 do
      if not original_loaders[package.loaders[i]] then
        table.remove(package.loaders, i)
      end
    end

    assert(ok, mod)
    assert.equal("@" .. vim.fs.normalize(module), debug.getinfo(mod.is_positive, "S").source)
  end)

  it("hands a require for an unresolved module to the next loader", function()
    local cwd = helper.test_data.full_path
    local module = helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    helper.test_data:create_file("lua/other.lua", "return { name = 'real other' }")

    local original_loaders = {}
    for _, loader in ipairs(package.loaders) do
      original_loaders[loader] = true
    end
    vim.opt.runtimepath:append(cwd)

    mutate.install(first_mutation(module, "swap-relational"), cwd)
    local ok, other = pcall(require, "other")

    package.loaded["other"] = nil
    vim.opt.runtimepath:remove(cwd)
    for i = #package.loaders, 1, -1 do
      if not original_loaders[package.loaders[i]] then
        table.remove(package.loaders, i)
      end
    end

    assert(ok, other)
    -- WHY: the loader resolves only mod, so a require for another module must
    -- fall through to the real one rather than being served mod's mutated source.
    -- NOT: asserting mod itself, which never exercises the unresolved-name path.
    assert.equal("real other", other.name)
  end)

  it("reports that the mutation was not applied when the module is never required", function()
    local cwd = helper.test_data.full_path
    helper.test_data:create_file(
      "lua/mod.lua",
      [[
local M = {}
function M.is_positive(n)
  return n > 0
end
return M
]]
    )
    local unused = helper.test_data:create_file(
      "lua/unused.lua",
      [[
local M = {}
function M.f(a, b)
  return a < b
end
return M
]]
    )
    local item = work.plan({ helper.test_data:create_file("spec/mod_spec.lua", SPEC) })[1]

    local outcome = launch(item, first_mutation(unused, "swap-relational"), cwd)

    assert.is_false(outcome.mutation_applied)
    assert.equal("passed", outcome.results[1].status)
  end)
end)
