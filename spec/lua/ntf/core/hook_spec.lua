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
