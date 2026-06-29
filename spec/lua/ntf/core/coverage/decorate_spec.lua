local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local helper = require("ntf.test.helper")

local ns = vim.api.nvim_create_namespace("ntf.coverage")

local SOURCE = table.concat({
  "local M = {}", -- 1 code, hit
  "-- comment", -- 2 not code
  "function M.f()", -- 3 code, hit
  "  return 1", -- 4 code, missed
  "end", -- 5 lone end, not code
}, "\n")

--- Map row (0-based) -> sign_hl_group of the coverage extmarks in `bufnr`.
local function signs(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(marks) do
    result[mark[2]] = mark[4].sign_hl_group
  end
  return result
end

describe("ntf.core.coverage.decorate via ntf.decorate_coverage", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("signs covered and coverable-but-missed lines, skipping non-code lines", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    -- max=4: line 1 hit, 2 unhit (comment), 3 hit, 4 unhit (missed).
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    ntf.decorate_coverage({ path = stats, buffer = bufnr })

    assert.same({
      [0] = "NtfCoverageCovered", -- line 1
      [2] = "NtfCoverageCovered", -- line 3
      [3] = "NtfCoverageMissed", -- line 4
    }, signs(bufnr))
  end)

  it("clears the decoration with enable = false", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    ntf.decorate_coverage({ path = stats, buffer = bufnr })
    ntf.decorate_coverage({ enable = false, buffer = bufnr })

    assert.same({}, signs(bufnr))
  end)

  it("leaves the buffer untouched when its file is not in the stats", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local stats = helper.test_data:create_file("luacov.stats.out", "1:/other.lua\n1\n")

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    ntf.decorate_coverage({ path = stats, buffer = bufnr })

    assert.same({}, signs(bufnr))
  end)
end)

describe("ntf.is_decorated_coverage", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("is false before decorating and true after, then false again when cleared", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    assert.is_false(ntf.is_decorated_coverage({ buffer = bufnr }))

    ntf.decorate_coverage({ path = stats, buffer = bufnr })
    assert.is_true(ntf.is_decorated_coverage({ buffer = bufnr }))

    ntf.decorate_coverage({ enable = false, buffer = bufnr })
    assert.is_false(ntf.is_decorated_coverage({ buffer = bufnr }))
  end)

  it("reports per buffer", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local decorated = vim.api.nvim_get_current_buf()
    ntf.decorate_coverage({ path = stats, buffer = decorated })
    local other = vim.api.nvim_create_buf(false, true)

    assert.is_true(ntf.is_decorated_coverage({ buffer = decorated }))
    assert.is_false(ntf.is_decorated_coverage({ buffer = other }))
  end)
end)
