local ntf = require("ntf")
local describe, it, finally, assert = ntf.describe, ntf.it, ntf.finally, ntf.assert
local runtime = require("ntf.core.runtime")

describe("ntf.core.runtime.setup", function()
  it("prepends the working directory, so a module there wins over one of the same name", function()
    local original = vim.o.runtimepath
    finally(function()
      vim.o.runtimepath = original
    end)
    vim.o.runtimepath = vim.fn.tempname()

    runtime.setup()

    assert.equal(vim.fs.normalize(vim.fn.getcwd()), vim.fs.normalize(vim.opt.runtimepath:get()[1]))
  end)
end)
