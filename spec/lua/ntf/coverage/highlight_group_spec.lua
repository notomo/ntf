local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
require("ntf.coverage.highlight_group")

describe("ntf.coverage.highlight_group", function()
  it("keeps the groups linked across a colorscheme change", function()
    vim.cmd.colorscheme("blue")

    assert.equal("DiffAdd", vim.api.nvim_get_hl(0, { name = "NtfCoverageCovered" }).link)
    assert.equal("DiffDelete", vim.api.nvim_get_hl(0, { name = "NtfCoverageMissed" }).link)
  end)
end)
