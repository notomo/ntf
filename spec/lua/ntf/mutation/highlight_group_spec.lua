local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
require("ntf.mutation.highlight_group")

describe("ntf.mutation.highlight_group", function()
  it("keeps the group linked across a colorscheme change", function()
    vim.cmd.colorscheme("blue")

    assert.equal("WarningMsg", vim.api.nvim_get_hl(0, { name = "NtfMutationSurvived" }).link)
  end)
end)
