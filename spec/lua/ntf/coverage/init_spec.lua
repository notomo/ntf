local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local coverage = require("ntf.coverage")
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

describe("ntf.coverage.decorate", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("signs covered and coverable-but-missed lines, skipping non-code lines", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    -- max=4: line 1 hit, 2 unhit (comment), 3 hit, 4 unhit (missed).
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [0] = "NtfCoverageCovered", -- line 1
      [2] = "NtfCoverageCovered", -- line 3
      [3] = "NtfCoverageMissed", -- line 4
    }, signs(bufnr))
  end)

  it("places no sign past the buffer's end when the stats file is stale", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    -- Stats from an older, longer version of the file: hits on lines 6-8, which
    -- no longer exist in the buffer.
    local stats = helper.test_data:create_file("luacov.stats.out", ("8:%s\n1 0 1 0 0 1 1 1\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [0] = "NtfCoverageCovered", -- line 1
      [2] = "NtfCoverageCovered", -- line 3
      [3] = "NtfCoverageMissed", -- line 4
    }, signs(bufnr))
  end)

  it("does not flag multi-line closure header lines as missed", function()
    -- LuaJIT attributes the closure-creating instruction to the closing `end`,
    -- so the `function(...)` header lines never get a hit; they must not be
    -- treated as coverable-but-missed.
    local header_src = table.concat({
      "local a = function()", -- 1 closure header, unhit
      "  return 1", -- 2 code, missed (closure never called)
      "end", -- 3 lone end, hit (closure creation lands here)
      "return function()", -- 4 closure header, unhit
      "  return 2", -- 5 code, missed
      "end", -- 6 lone end, hit
    }, "\n")
    local src = helper.test_data:create_file("mod.lua", header_src)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("6:%s\n0 0 1 0 0 1\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [1] = "NtfCoverageMissed", -- line 2
      [2] = "NtfCoverageCovered", -- line 3 (end, hit)
      [4] = "NtfCoverageMissed", -- line 5
      [5] = "NtfCoverageCovered", -- line 6 (end, hit)
    }, signs(bufnr))
  end)

  it("does not flag explicit `= nil` assignment lines as missed", function()
    -- Assigning nil to a table field emits no bytecode, so the line can never
    -- get a hit; it must not be treated as coverable-but-missed.
    local nil_src = table.concat({
      "local t = {", -- 1 code, hit (constructor opener)
      "  path = nil,", -- 2 = nil, unhit -> not coverable (no sign)
      "}", -- 3 lone close, not code
      "return t", -- 4 code, missed
    }, "\n")
    local src = helper.test_data:create_file("mod.lua", nil_src)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 0 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [0] = "NtfCoverageCovered", -- line 1
      [3] = "NtfCoverageMissed", -- line 4
    }, signs(bufnr))
  end)

  it("does not flag table fields, bare locals, or opener braces as missed", function()
    -- LuaJIT collapses a table constructor onto its opening line, merges
    -- consecutive bare `local`s onto the first, and never hits a lone `{`. None
    -- of those lines can receive a hit, so they must not be coverable. A genuine
    -- unhit call line, by contrast, must still show as missed.
    local mixed_src = table.concat({
      "local t1 = {", -- 1  opener, hit
      '  one = "one",', -- 2  field, never hit -> not coverable
      '  two = "two",', -- 3  field, never hit -> not coverable
      "}", -- 4  lone close
      "local x", -- 5  bare local (first), hit
      "local y", -- 6  bare local, never hit -> not coverable
      "local t2 = {", -- 7  opener, hit
      "  f(),", -- 8  call, unhit -> missed
      "}", -- 9  lone close
      "return t1, t2, x, y", -- 10 return, hit
    }, "\n")
    local src = helper.test_data:create_file("mod.lua", mixed_src)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("10:%s\n1 0 0 0 1 0 1 0 0 1\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [0] = "NtfCoverageCovered", -- line 1 opener
      [4] = "NtfCoverageCovered", -- line 5 bare local (hit)
      [6] = "NtfCoverageCovered", -- line 7 opener
      [7] = "NtfCoverageMissed", -- line 8 unhit call
      [9] = "NtfCoverageCovered", -- line 10 return
    }, signs(bufnr))
  end)

  it("does not flag the receiver line of a multi-line method chain as missed", function()
    -- A call node begins on its receiver line (`vim` alone), but LuaJIT lands the
    -- hit on the `arguments` line (`.iter(...)`). The receiver line must not be
    -- coverable; the call line carries the coverage.
    local chain_src = table.concat({
      "local t = {", -- 1  opener, hit
      "  vim", -- 2  receiver, never hit -> not coverable
      "    .iter(x)", -- 3  call arguments, hit
      "    :totable(),", -- 4  call arguments, unhit -> missed
      "}", -- 5  lone close
      "return t", -- 6  return, hit
    }, "\n")
    local src = helper.test_data:create_file("mod.lua", chain_src)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("6:%s\n1 0 1 0 0 1\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [0] = "NtfCoverageCovered", -- line 1 opener
      [2] = "NtfCoverageCovered", -- line 3 .iter(x) (hit)
      [3] = "NtfCoverageMissed", -- line 4 :totable() (unhit call)
      [5] = "NtfCoverageCovered", -- line 6 return
    }, signs(bufnr))
  end)

  it("does not flag a `x = a or function() end` header as missed", function()
    -- The value is `existing or function()`: LuaJIT lands the hit on the closure
    -- line, not the assignment's opening line, so the header must not count as
    -- coverable (the closure body still carries its own coverage).
    local or_src = table.concat({
      "local cb = existing", -- 1  header (a or closure), never hit -> not coverable
      "  or function()", -- 2  closure creation, hit
      "    return 1", -- 3  closure body, unhit -> missed
      "  end", -- 4  lone end
      "return cb", -- 5  return, hit
    }, "\n")
    local src = helper.test_data:create_file("mod.lua", or_src)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("5:%s\n0 1 0 0 1\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })

    assert.same({
      [1] = "NtfCoverageCovered", -- line 2 closure creation (hit)
      [2] = "NtfCoverageMissed", -- line 3 unhit closure body
      [4] = "NtfCoverageCovered", -- line 5 return
    }, signs(bufnr))
  end)

  it("clears the decoration with enable = false", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = bufnr })
    coverage.decorate({ enable = false, buffer = bufnr })

    assert.same({}, signs(bufnr))
  end)

  it("errors when the coverage file does not exist", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local path = helper.test_data:path("missing.stats.out")

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, err = pcall(coverage.decorate, { path = path, buffer = bufnr })

    assert.is_false(ok)
    assert.match("%[ntf%] coverage file is not found: ", err)
  end)

  it("leaves the buffer untouched when its file is not in the stats", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
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
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    assert.is_false(coverage.is_decorated({ buffer = bufnr }))

    coverage.decorate({ path = stats, buffer = bufnr })
    assert.is_true(coverage.is_decorated({ buffer = bufnr }))

    coverage.decorate({ enable = false, buffer = bufnr })
    assert.is_false(coverage.is_decorated({ buffer = bufnr }))
  end)

  it("reports per buffer", function()
    local src = helper.test_data:create_file("mod.lua", SOURCE)
    local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
    local stats = helper.test_data:create_file("luacov.stats.out", ("4:%s\n1 0 1 0\n"):format(file))

    vim.cmd.edit(src)
    local decorated = vim.api.nvim_get_current_buf()
    coverage.decorate({ path = stats, buffer = decorated })
    local other = vim.api.nvim_create_buf(false, true)

    assert.is_true(coverage.is_decorated({ buffer = decorated }))
    assert.is_false(coverage.is_decorated({ buffer = other }))
  end)
end)
