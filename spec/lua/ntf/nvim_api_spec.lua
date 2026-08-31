local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert

local ns = vim.api.nvim_create_namespace("ntf.nvim_api_spec")

describe("nvim_buf_get_lines", function()
  it("returns the whole buffer for 0..-1 whether or not indexing is strict", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b" })

    assert.same(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), vim.api.nvim_buf_get_lines(bufnr, 0, -1, true))
  end)
end)

describe("nvim_buf_clear_namespace", function()
  it("clears through the end of the buffer for any negative line_end, not only -1", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
    local last_row = 2
    vim.api.nvim_buf_set_extmark(bufnr, ns, last_row, 0, {})

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -2)

    assert.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
  end)
end)

describe("nvim_get_runtime_file", function()
  it("names the same first file whether it is asked for one match or for all of them", function()
    local pattern = "lua/ntf/init.lua"

    assert.equal(vim.api.nvim_get_runtime_file(pattern, false)[1], vim.api.nvim_get_runtime_file(pattern, true)[1])
  end)
end)
