local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local mutation = require("ntf.mutation")
local helper = require("ntf.test.helper")

local ns = vim.api.nvim_create_namespace("ntf.mutation")

local SOURCE = table.concat({
  "local M = {}",
  "function M.f(a, b)",
  "  return a < b",
  "end",
  "return M",
}, "\n")

--- @param row integer 1-based
--- @param status string
local function record(row, status)
  return {
    row = row,
    col = 9,
    end_row = row,
    end_col = 10,
    operator = "swap-relational",
    original = "<",
    replacement = "<=",
    status = status,
  }
end

--- Map row (0-based) -> the extmark's sign highlight and virtual text.
local function marks(bufnr)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(extmarks) do
    result[mark[2]] = {
      sign_hl_group = mark[4].sign_hl_group,
      virt_text = mark[4].virt_text and mark[4].virt_text[1][1] or nil,
    }
  end
  return result
end

--- @param records table[]
--- @return string src, string results_file
local function project(records)
  local src = helper.test_data:create_file("mod.lua", SOURCE)
  local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
  local results_file = helper.test_data:create_file(
    "ntf-mutation.json",
    vim.json.encode({
      version = 1,
      score = 50,
      counts = { killed = 1, timeout = 0, survived = 1, no_coverage = 0, not_applied = 0 },
      files = { [file] = records },
    })
  )
  return src, results_file
end

describe("ntf.mutation.decorate", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("marks the surviving mutants with the change they got away with", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({
      [2] = { sign_hl_group = "NtfMutationSurvived", virt_text = " swap-relational: < -> <=" },
    }, marks(bufnr))
  end)

  it("draws nothing for a mutant the tests detected", function()
    local src, results_file = project({ record(3, "killed"), record(1, "no_coverage") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({}, marks(bufnr))
  end)

  it("places no mark past the buffer's end when the results are stale", function()
    local src, results_file = project({ record(99, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({}, marks(bufnr))
  end)

  it("draws nothing for a buffer the results do not mention", function()
    local _, results_file = project({ record(3, "survived") })
    local other = helper.test_data:create_file("other.lua", SOURCE)

    vim.cmd.edit(other)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({}, marks(bufnr))
  end)

  it("clears the decoration when disabled", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })
    mutation.decorate({ path = results_file, buffer = bufnr, enable = false })

    assert.same({}, marks(bufnr))
  end)

  it("errors when the results file does not exist", function()
    local ok, err = pcall(mutation.decorate, { path = helper.test_data:path("nope.json") })

    assert.is_false(ok)
    assert.match("%[ntf%] mutation results file is not found: ", err)
  end)
end)

describe("ntf.mutation.is_decorated", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("is true only while the decoration is drawn", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    assert.is_false(mutation.is_decorated({ buffer = bufnr }))

    mutation.decorate({ path = results_file, buffer = bufnr })
    assert.is_true(mutation.is_decorated({ buffer = bufnr }))

    mutation.decorate({ path = results_file, buffer = bufnr, enable = false })
    assert.is_false(mutation.is_decorated({ buffer = bufnr }))
  end)
end)
