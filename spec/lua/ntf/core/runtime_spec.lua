local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local runtime = require("ntf.core.runtime")
local helper = require("ntf.test.helper")

--- @param body string[] the lines of the returned table
--- @return string path
local function process_hook(body)
  return helper.test_data:create_file("process_hook.lua", table.concat(vim.list_extend({ "return {" }, body), "\n"))
end

describe("ntf.core.runtime.setup", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("prepends the working directory, so a module there wins over one of the same name", function()
    local original = vim.o.runtimepath
    finally(function()
      vim.o.runtimepath = original
    end)
    vim.o.runtimepath = vim.fn.tempname()

    runtime.setup()

    assert.equal(vim.fs.normalize(vim.fn.getcwd()), vim.fs.normalize(vim.opt.runtimepath:get()[1]))
  end)

  it(
    "runs the process hook with the working directory already prepended, which is what it puts a dependency beside",
    function()
      local original = vim.o.runtimepath
      finally(function()
        vim.o.runtimepath = original
      end)
      vim.o.runtimepath = vim.fn.tempname()
      local path = process_hook({
        "  setup = function()",
        "    vim.g.ntf_runtime_spec_head = vim.opt.runtimepath:get()[1]",
        "  end,",
        "}",
      })

      local rejected = runtime.setup(path)

      assert.is_nil(rejected)
      assert.equal(vim.fs.normalize(vim.fn.getcwd()), vim.fs.normalize(vim.g.ntf_runtime_spec_head))
    end
  )

  it("returns why a module cannot be a process hook, leaving its setup unrun", function()
    local path = process_hook({
      "  setup = function()",
      '    vim.g.ntf_runtime_spec_head = "ran"',
      "  end,",
      "  teardown = function() end,",
      "}",
    })

    local rejected = runtime.setup(path)

    assert.match("takes no teardown", rejected)
    assert.is_nil(vim.g.ntf_runtime_spec_head)
  end)
end)
