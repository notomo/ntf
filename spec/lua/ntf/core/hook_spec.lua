local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local hook = require("ntf.core.hook")
local helper = require("ntf.test.helper")

-- WHY: a test further down proves a rejected setup did not run by finding this
-- global unset, which only holds where nothing left it set.
-- NOT: leaving it to the process ending, which is not what separates two tests
-- that share one.
local function clear_global()
  finally(function()
    vim.g.ntf_hook_spec = nil
  end)
end

describe("ntf.core.hook.load", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("loads setup and teardown from the module file", function()
    clear_global()
    local path = helper.test_data:create_file(
      "hook.lua",
      table.concat({
        "return {",
        "  setup = function()",
        '    vim.g.ntf_hook_spec = "setup"',
        "  end,",
        "  teardown = function()",
        '    vim.g.ntf_hook_spec = "teardown"',
        "  end,",
        "}",
      }, "\n")
    )

    local loaded = hook.load("--test-hook", path)
    loaded.setup()
    assert.equal("setup", vim.g.ntf_hook_spec)
    loaded.teardown()
    assert.equal("teardown", vim.g.ntf_hook_spec)
  end)

  it("fills a missing teardown with a noop", function()
    clear_global()
    local path = helper.test_data:create_file(
      "hook.lua",
      table.concat({
        "return {",
        "  setup = function()",
        '    vim.g.ntf_hook_spec = "setup"',
        "  end,",
        "}",
      }, "\n")
    )

    local loaded = hook.load("--test-hook", path)
    loaded.setup()
    loaded.teardown()
    assert.equal("setup", vim.g.ntf_hook_spec)
  end)

  it("rejects a module that returns a function rather than a table of hooks", function()
    local path = helper.test_data:create_file("hook.lua", "return function() end")

    local rejected = hook.load("--test-hook", path)

    assert.match(vim.pesc(path), rejected)
    assert.match("returns a function", rejected)
    assert.match("returns a table of hooks", rejected)
  end)

  it("names the flag the rejected module was given to, which alone says which hook to fix", function()
    local path = helper.test_data:create_file("hook.lua", "return function() end")

    local rejected = hook.load("--global-hook", path)

    assert.match("^%-%-global%-hook module " .. vim.pesc(path), rejected)
  end)

  it("rejects a module that returns nothing at all", function()
    local path = helper.test_data:create_file("hook.lua", "local unused = 1")

    local rejected = hook.load("--test-hook", path)

    assert.match("returns a nil", rejected)
  end)

  it("rejects a module carrying a single key no hook is read from", function()
    local path = helper.test_data:create_file("hook.lua", "return { setUp = function() end }")

    local rejected = hook.load("--test-hook", path)

    assert.match("returns keys no hook is read from: setUp", rejected)
  end)

  it("names every key no hook is read from, not the first one it meets", function()
    local path = helper.test_data:create_file(
      "hook.lua",
      "return { setUp = function() end, tearDown = function() end, beforeAll = function() end }"
    )

    local rejected = hook.load("--test-hook", path)

    assert.match("returns keys no hook is read from: ", rejected)
    assert.match("beforeAll", rejected)
    assert.match("setUp", rejected)
    assert.match("tearDown", rejected)
    assert.match("takes setup and teardown", rejected)
  end)

  it("rejects a module whose setup is not a function", function()
    local path = helper.test_data:create_file("hook.lua", "return { setup = 42 }")

    local rejected = hook.load("--test-hook", path)

    assert.match("gives its setup a number", rejected)
  end)

  it("rejects a module whose teardown is not a function", function()
    local path = helper.test_data:create_file("hook.lua", "return { teardown = 42 }")

    local rejected = hook.load("--test-hook", path)

    assert.match("gives its teardown a number", rejected)
  end)

  it("returns noops when the path is nil or empty", function()
    for _, loaded in ipairs({ hook.load("--test-hook", nil), hook.load("--test-hook", "") }) do
      loaded.setup()
      loaded.teardown()
    end
  end)
end)

describe("ntf.core.hook.load_setup", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("returns the setup the module provides", function()
    clear_global()
    local path = helper.test_data:create_file(
      "process_hook.lua",
      table.concat({
        "return {",
        "  setup = function()",
        '    vim.g.ntf_hook_spec = "setup"',
        "  end,",
        "}",
      }, "\n")
    )

    local setup = hook.load_setup(path)

    assert.equal("function", type(setup))
    setup()
    assert.equal("setup", vim.g.ntf_hook_spec)
  end)

  it("rejects a module providing a teardown, naming the hooks one belongs in", function()
    local path = helper.test_data:create_file(
      "process_hook.lua",
      table.concat({
        "return {",
        "  setup = function()",
        '    vim.g.ntf_hook_spec = "setup"',
        "  end,",
        "  teardown = function() end,",
        "}",
      }, "\n")
    )

    local rejected = hook.load_setup(path)

    assert.match("%-%-process%-hook takes no teardown", rejected)
    assert.match(vim.pesc(path), rejected)
    assert.match("%-%-test%-hook", rejected)
    assert.match("%-%-global%-hook", rejected)
    assert.is_nil(vim.g.ntf_hook_spec)
  end)

  it("rejects a module that returns no table, before it looks for a teardown", function()
    local path = helper.test_data:create_file("process_hook.lua", "return function() end")

    local rejected = hook.load_setup(path)

    assert.match("^%-%-process%-hook module " .. vim.pesc(path), rejected)
    assert.match("returns a table of hooks", rejected)
  end)

  it("returns a noop for a module without a setup, and for no module at all", function()
    local path = helper.test_data:create_file("process_hook.lua", "return {}")

    for _, setup in ipairs({ hook.load_setup(path), hook.load_setup(nil), hook.load_setup("") }) do
      setup()
    end
  end)
end)
