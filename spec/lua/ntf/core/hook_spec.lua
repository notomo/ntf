local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local hook = require("ntf.core.hook")
local helper = require("ntf.test.helper")

describe("ntf.core.hook.load", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("loads setup and teardown from the module file", function()
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

    local loaded = hook.load(path)
    loaded.setup()
    assert.equal("setup", vim.g.ntf_hook_spec)
    loaded.teardown()
    assert.equal("teardown", vim.g.ntf_hook_spec)
  end)

  it("fills a missing teardown with a noop", function()
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

    local loaded = hook.load(path)
    loaded.setup()
    loaded.teardown()
    assert.equal("setup", vim.g.ntf_hook_spec)
  end)

  it("returns noops when the module does not return a table", function()
    local path = helper.test_data:create_file("hook.lua", "return 42")

    local loaded = hook.load(path)
    loaded.setup()
    loaded.teardown()
  end)

  it("returns noops when the path is nil or empty", function()
    for _, loaded in ipairs({ hook.load(nil), hook.load("") }) do
      loaded.setup()
      loaded.teardown()
    end
  end)
end)

describe("ntf.core.hook.load_setup", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("returns the setup the module provides", function()
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

  it("returns a noop for a module without a setup, and for no module at all", function()
    local path = helper.test_data:create_file("process_hook.lua", "return {}")

    for _, setup in ipairs({ hook.load_setup(path), hook.load_setup(nil), hook.load_setup("") }) do
      setup()
    end
  end)
end)
