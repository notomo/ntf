local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local plugin_helper = require("ntf.helper")
local helper = require("ntf.test.helper")

describe("ntf.helper.find_plugin_root", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("returns the plugin root directory for a plugin on runtimepath", function()
    assert.equal(helper.root, plugin_helper.find_plugin_root("ntf"))
  end)

  it("returns the plugin root for a plugin whose own path has a lua directory above it", function()
    local plugin_name = "ntf_under_a_lua_directory"
    local plugin_root = helper.test_data:create_dir(vim.fs.joinpath("lua", "upstream", plugin_name))
    helper.test_data:create_file(vim.fs.joinpath("lua", "upstream", plugin_name, "lua", plugin_name, "init.lua"))
    vim.opt.runtimepath:append(plugin_root)

    assert.equal(plugin_root, plugin_helper.find_plugin_root(plugin_name))
  end)

  it("takes a first runtime file nvim returns the same whether or not all matches are asked for", function()
    local pattern = "lua/ntf/*"

    assert.equal(vim.api.nvim_get_runtime_file(pattern, false)[1], vim.api.nvim_get_runtime_file(pattern, true)[1])
  end)

  it("errors when no module matches the plugin name", function()
    local ok, err = pcall(plugin_helper.find_plugin_root, "ntf_does_not_exist")
    assert.is_false(ok)
    assert.match("plugin root is not found", err)
  end)
end)

describe("ntf.helper.get_module_root", function()
  it("returns the leading segment of a dotted module name", function()
    assert.equal("plugin_name", plugin_helper.get_module_root("plugin_name.module1"))
  end)

  it("returns nested submodule root", function()
    assert.equal("plugin_name", plugin_helper.get_module_root("plugin_name.sub.module"))
  end)

  it("returns the whole name when there is no dot", function()
    assert.equal("plugin_name", plugin_helper.get_module_root("plugin_name"))
  end)
end)
