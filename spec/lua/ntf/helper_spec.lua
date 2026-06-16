local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local plugin_helper = require("ntf.helper")
local helper = require("ntf.test.helper")

describe("ntf.helper.find_plugin_root", function()
  it("returns the plugin root directory for a plugin on runtimepath", function()
    assert.equal(helper.root, plugin_helper.find_plugin_root("ntf"))
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
