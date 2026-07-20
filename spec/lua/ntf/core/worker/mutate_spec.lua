local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
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

    -- `n > 0` becomes `n >= 0`, so is_positive(0) turns true.
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
    -- A hook that pulls the module in first leaves it in package.loaded, where a
    -- plain `require` would never reach the mutation loader. (ntf running its own
    -- specs is the same situation.)
    local hook = helper.test_data:create_file(
      "hook.lua",
      [[
require("mod")
return {}
]]
    )
    local item = work.plan({ helper.test_data:create_file("spec/mod_spec.lua", SPEC) })[1]

    local outcome = launch(item, first_mutation(module, "swap-relational"), cwd, hook)

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
    -- On the runtimepath too, so Neovim's own loader could also resolve the
    -- module: this pins the install position, where any later slot would let
    -- the original win.
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
    -- Just after the preload loader, by index rather than by requiring a
    -- runtimepath-resolvable module: a mutation trial's worker has its own
    -- mutation loader installed already, which would mask a one-slot shift.
    assert.equal(2, installed_index)
    assert.is_false(applied_before)
    assert.is_true(applied_after)
    -- `n > 0` became `n >= 0`, so only the mutated source is true at 0.
    assert.is_true(mod.is_positive(0))
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
