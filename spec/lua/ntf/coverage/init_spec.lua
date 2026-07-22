local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local coverage = require("ntf.coverage")
local helper = require("ntf.test.helper")

local ns = vim.api.nvim_create_namespace("ntf.coverage")

local COVERED = "NtfCoverageCovered"
local MISSED = "NtfCoverageMissed"

--- @class CoverageLine
--- @field code string one source line of the measured module
--- @field hit boolean whether the stats file records a hit for the line
--- @field sign string? sign highlight group the line must get, nil when it must get no sign

--- @type CoverageLine[]
local MODULE = {
  { code = "local M = {}", hit = true, sign = COVERED },
  { code = "-- comment", hit = false },
  { code = "function M.f()", hit = true, sign = COVERED },
  { code = "  return 1", hit = false, sign = MISSED },
  { code = "end", hit = false },
}

--- @param bufnr integer
--- @return table<integer,string> sign_hl_group of the coverage extmarks by 0-based row
local function signs(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(marks) do
    result[mark[2]] = mark[4].sign_hl_group
  end
  return result
end

--- @param lines CoverageLine[]
--- @return string path of the written module
local function create_module(lines)
  local codes = vim.tbl_map(function(line)
    return line.code
  end, lines)
  return helper.test_data:create_file("mod.lua", table.concat(codes, "\n"))
end

--- @param src string module path
--- @param hits integer[] hit count per line, starting at line 1
--- @return string path of the written stats file
local function create_stats(src, hits)
  local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
  return helper.test_data:create_file("luacov.stats.out", ("%d:%s\n%s\n"):format(#hits, file, table.concat(hits, " ")))
end

--- @param lines CoverageLine[]
--- @return integer[] hit count per line
local function hits_of(lines)
  return vim.tbl_map(function(line)
    return line.hit and 1 or 0
  end, lines)
end

--- @param lines CoverageLine[]
--- @return table<integer,string> expected sign highlight group by 0-based row
local function expected_signs(lines)
  local expected = {}
  for i, line in ipairs(lines) do
    if line.sign then
      expected[i - 1] = line.sign
    end
  end
  return expected
end

--- @param lines CoverageLine[]
--- @return table<integer,string> sign highlight group by 0-based row
local function decorated_signs(lines)
  local src = create_module(lines)
  local stats = create_stats(src, hits_of(lines))

  vim.cmd.edit(src)
  local bufnr = vim.api.nvim_get_current_buf()
  coverage.decorate({ path = stats, buffer = bufnr })
  return signs(bufnr)
end

describe("ntf.coverage.decorate", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("signs covered and coverable-but-missed lines, skipping non-code lines", function()
    assert.same(expected_signs(MODULE), decorated_signs(MODULE))
  end)

  it("places no sign past the buffer's end when the stats file is stale", function()
    local src = create_module(MODULE)
    local hits_of_the_longer_previous_file = { 1, 0, 1, 0, 0, 1, 1, 1 }
    local stats = create_stats(src, hits_of_the_longer_previous_file)

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same(expected_signs(MODULE), signs(bufnr))
  end)

  it("does not flag multi-line closure header lines as missed", function()
    --- @type CoverageLine[]
    local closure_headers = {
      { code = "local a = function()", hit = false },
      { code = "  return 1", hit = false, sign = MISSED },
      { code = "end", hit = true, sign = COVERED },
      { code = "return function()", hit = false },
      { code = "  return 2", hit = false, sign = MISSED },
      { code = "end", hit = true, sign = COVERED },
    }

    assert.same(expected_signs(closure_headers), decorated_signs(closure_headers))
  end)

  it("does not flag explicit `= nil` assignment lines as missed", function()
    --- @type CoverageLine[]
    local nil_field = {
      { code = "local t = {", hit = true, sign = COVERED },
      { code = "  path = nil,", hit = false },
      { code = "}", hit = false },
      { code = "return t", hit = false, sign = MISSED },
    }

    assert.same(expected_signs(nil_field), decorated_signs(nil_field))
  end)

  it("does not flag table fields, bare locals, or opener braces as missed", function()
    --- @type CoverageLine[]
    local fields_and_locals = {
      { code = "local t1 = {", hit = true, sign = COVERED },
      { code = '  one = "one",', hit = false },
      { code = '  two = "two",', hit = false },
      { code = "}", hit = false },
      { code = "local x", hit = true, sign = COVERED },
      { code = "local y", hit = false },
      { code = "local t2 = {", hit = true, sign = COVERED },
      { code = "  f(),", hit = false, sign = MISSED },
      { code = "}", hit = false },
      { code = "return t1, t2, x, y", hit = true, sign = COVERED },
    }

    assert.same(expected_signs(fields_and_locals), decorated_signs(fields_and_locals))
  end)

  it("does not flag the receiver line of a multi-line method chain as missed", function()
    --- @type CoverageLine[]
    local method_chain = {
      { code = "local t = {", hit = true, sign = COVERED },
      { code = "  vim", hit = false },
      { code = "    .iter(x)", hit = true, sign = COVERED },
      { code = "    :totable(),", hit = false, sign = MISSED },
      { code = "}", hit = false },
      { code = "return t", hit = true, sign = COVERED },
    }

    assert.same(expected_signs(method_chain), decorated_signs(method_chain))
  end)

  it("does not flag a `x = a or function() end` header as missed", function()
    --- @type CoverageLine[]
    local or_closure = {
      { code = "local cb = existing", hit = false },
      { code = "  or function()", hit = true, sign = COVERED },
      { code = "    return 1", hit = false, sign = MISSED },
      { code = "  end", hit = false },
      { code = "return cb", hit = true, sign = COVERED },
    }

    assert.same(expected_signs(or_closure), decorated_signs(or_closure))
  end)

  it("clears the decoration with enable = false", function()
    local src = create_module(MODULE)
    local stats = create_stats(src, hits_of(MODULE))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })
    coverage.decorate({ enable = false, buffer = bufnr })

    assert.same({}, signs(bufnr))
  end)

  it("errors when the coverage file does not exist", function()
    local src = create_module(MODULE)
    local path = helper.test_data:path("missing.stats.out")

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, err = pcall(coverage.decorate, { path = path, buffer = bufnr })

    assert.is_false(ok)
    assert.match("%[ntf%] coverage file is not found: ", err)
  end)

  it("leaves the buffer untouched when its file is not in the stats", function()
    local src = create_module(MODULE)
    local stats = helper.test_data:create_file("luacov.stats.out", "1:/other.lua\n1\n")

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({}, signs(bufnr))
  end)
end)

describe("ntf.coverage.is_decorated", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("is false before decorating and true after, then false again when cleared", function()
    local src = create_module(MODULE)
    local stats = create_stats(src, hits_of(MODULE))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    assert.is_false(coverage.is_decorated({ buffer = bufnr }))

    coverage.decorate({ path = stats, buffer = bufnr })
    assert.is_true(coverage.is_decorated({ buffer = bufnr }))

    coverage.decorate({ enable = false, buffer = bufnr })
    assert.is_false(coverage.is_decorated({ buffer = bufnr }))
  end)

  it("reports per buffer", function()
    local src = create_module(MODULE)
    local stats = create_stats(src, hits_of(MODULE))

    vim.cmd.edit(src)
    local decorated = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = decorated })
    local other = vim.api.nvim_create_buf(false, true)

    assert.is_true(coverage.is_decorated({ buffer = decorated }))
    assert.is_false(coverage.is_decorated({ buffer = other }))
  end)
end)
