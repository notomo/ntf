local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local report = require("ntf.core.coverage.report")
local helper = require("ntf.test.helper")

--- @class SummaryLine
--- @field code string one source line of the measured module
--- @field hit boolean whether the merged stats record a hit for the line
--- @field coverable boolean whether the line belongs in the coverage denominator

--- @param lines SummaryLine[]
--- @param name string? file name of the measured module
--- @return string summary text
local function summary_of(lines, name)
  local codes = vim.tbl_map(function(line)
    return line.code
  end, lines)
  local src = helper.test_data:create_file(name or "mod.lua", table.concat(codes, "\n"))

  local hits = {}
  local max = 0
  for i, line in ipairs(lines) do
    if line.hit then
      hits[i] = 1
      max = i
    end
  end
  local merged = { [vim.fs.normalize(src)] = { max = max, lines = hits } }

  return report.summary(merged, helper.test_data.full_path)
end

--- @param lines SummaryLine[]
--- @return integer covered, integer coverable, string percentage
local function count(lines)
  local covered, coverable = 0, 0
  for _, line in ipairs(lines) do
    if line.coverable then
      coverable = coverable + 1
      if line.hit then
        covered = covered + 1
      end
    end
  end
  return covered, coverable, ("%.1f"):format(covered / coverable * 100)
end

--- @param lines SummaryLine[]
--- @return string pattern matching the whole-run coverage line
local function total_pattern(lines)
  local covered, coverable, percentage = count(lines)
  return ("Coverage: %s%%%% %%(%d/%d lines%%)"):format(percentage, covered, coverable)
end

--- @param name string file name of the measured module
--- @param lines SummaryLine[]
--- @return string pattern matching the per-file coverage line
local function file_pattern(name, lines)
  local covered, coverable, percentage = count(lines)
  return ("%s%%s+%s%%%% %%(%d/%d%%)"):format(name, percentage, covered, coverable)
end

describe("ntf.core.coverage.report.summary", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports covered/coverable percentages from source and hits", function()
    --- @type SummaryLine[]
    local lines = {
      { code = "local function f(x)", hit = true, coverable = true },
      { code = "  -- comment", hit = false, coverable = false },
      { code = "  if x then", hit = true, coverable = true },
      { code = "    return 1", hit = false, coverable = true },
      { code = "  end", hit = false, coverable = false },
      { code = "  return 0", hit = true, coverable = true },
      { code = "end", hit = false, coverable = false },
    }

    local text = summary_of(lines)

    assert.match(total_pattern(lines), text)
    assert.match(file_pattern("mod.lua", lines), text)
  end)

  it("excludes table fields and opener braces from the denominator", function()
    --- @type SummaryLine[]
    local lines = {
      { code = "local t1 = {", hit = true, coverable = true },
      { code = '  one = "one",', hit = false, coverable = false },
      { code = '  two = "two",', hit = false, coverable = false },
      { code = "}", hit = false, coverable = false },
      { code = "local t2 = {", hit = true, coverable = true },
      { code = "  f(),", hit = false, coverable = true },
      { code = "}", hit = false, coverable = false },
      { code = "return t1", hit = true, coverable = true },
    }

    local text = summary_of(lines)

    assert.match(total_pattern(lines), text)
  end)

  it("lists a never-executed file at 0%, naming none of its lines, since every one of them is missed", function()
    --- @type SummaryLine[]
    local lines = {
      { code = "local function f()", hit = false, coverable = false },
      { code = "  return 1", hit = false, coverable = true },
      { code = "end", hit = false, coverable = false },
      { code = "return f", hit = false, coverable = true },
    }

    local text = summary_of(lines)

    assert.match(file_pattern("mod.lua", lines), text)
    assert.no.match("missed", text)
  end)

  it("names the lines a file missed, folding a consecutive run into one range", function()
    --- @type SummaryLine[]
    local lines = {
      { code = "local M = {}", hit = true, coverable = true },
      { code = "function M.f(x)", hit = false, coverable = false },
      { code = "  print(x)", hit = false, coverable = true },
      { code = "  if x then", hit = false, coverable = true },
      { code = "    return 1", hit = false, coverable = true },
      { code = "  end", hit = false, coverable = false },
      { code = "  return 0", hit = false, coverable = true },
      { code = "end", hit = false, coverable = false },
      { code = "return M", hit = true, coverable = true },
    }

    local text = summary_of(lines)

    assert.match(file_pattern("mod.lua", lines) .. "%s+missed: 3%-5,7", text)
  end)

  it("names the missed lines ascending, whatever order the keys come out of the table in", function()
    local ascending = helper.unsorted_hash_order(function(salt)
      local rows = {}
      for i = 1, 6 do
        rows[i] = 1 + (i - 1) * salt
      end
      return rows
    end)

    local codes = {}
    for i = 1, ascending[#ascending] do
      codes[i] = ""
    end
    for _, row in ipairs(ascending) do
      codes[row] = "print(1)"
    end
    local src = helper.test_data:create_file("mod.lua", table.concat(codes, "\n"))
    local merged = { [vim.fs.normalize(src)] = { max = 1, lines = { [1] = 1 } } }

    local text = report.summary(merged, helper.test_data.full_path)

    local missed = {}
    for i = 2, #ascending do
      missed[#missed + 1] = ascending[i]
    end
    assert.match("missed: " .. table.concat(missed, ","), text)
  end)

  it("lays each row out padded to the longest name, sorted, under the run total", function()
    local one_line = helper.test_data:create_file("a.lua", "return 1")
    local two_lines = helper.test_data:create_file("bb.lua", table.concat({ "local x = 1", "return x" }, "\n"))
    local merged = {
      [vim.fs.normalize(one_line)] = { max = 1, lines = { [1] = 1 } },
      [vim.fs.normalize(two_lines)] = { max = 1, lines = { [1] = 1 } },
    }

    local text = report.summary(merged, helper.test_data.full_path)

    assert.equal(
      table.concat({
        "Coverage: 66.7% (2/3 lines)",
        "  a.lua   100.0% (1/1)",
        "  bb.lua   50.0% (1/2)  missed: 2",
        "",
      }, "\n"),
      text
    )
  end)

  it("orders the rows by name, whatever order the keys come out of the table in", function()
    local ascending = helper.unsorted_hash_order(function(salt)
      return vim.tbl_map(function(letter)
        return vim.fs.normalize(helper.test_data:path(("%s%d.lua"):format(letter, salt)))
      end, { "a", "b", "c", "d", "e", "f" })
    end)
    local merged = {}
    for _, path in ipairs(ascending) do
      helper.test_data:create_file(vim.fs.basename(path), "return 1")
      merged[path] = { max = 1, lines = { [1] = 1 } }
    end

    local text = report.summary(merged, helper.test_data.full_path)

    local listed = {}
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
      local name = line:match("^  (%S+)")
      if name then
        table.insert(listed, name)
      end
    end
    assert.same(vim.tbl_map(vim.fs.basename, ascending), listed)
  end)

  it("closes each source file it read", function()
    local path = vim.fs.normalize(helper.test_data:create_file("mod.lua", "return 1"))
    local merged = { [path] = { max = 1, lines = { [1] = 1 } } }

    assert.is_false(helper.leaves_file_open(path, function()
      report.summary(merged, helper.test_data.full_path)
    end))
  end)

  it("leaves out a measured file that can no longer be read", function()
    local merged = { [vim.fs.normalize(helper.test_data:path("gone.lua"))] = { max = 1, lines = { [1] = 1 } } }

    assert.match("Coverage: n/a", report.summary(merged, helper.test_data.full_path))
  end)

  it("leaves a file with no coverable line out of the listing", function()
    local measured = helper.test_data:create_file("a.lua", "return 1")
    local comment_only = helper.test_data:create_file("b.lua", "-- just a comment")
    local merged = {
      [vim.fs.normalize(measured)] = { max = 1, lines = { [1] = 1 } },
      [vim.fs.normalize(comment_only)] = { max = 0, lines = {} },
    }

    local text = report.summary(merged, helper.test_data.full_path)

    assert.equal(table.concat({ "Coverage: 100.0% (1/1 lines)", "  a.lua  100.0% (1/1)", "" }, "\n"), text)
  end)

  it("shows names relative to a working directory handed over with a trailing slash", function()
    local measured = helper.test_data:create_file("a.lua", "return 1")
    local merged = { [vim.fs.normalize(measured)] = { max = 1, lines = { [1] = 1 } } }

    local text = report.summary(merged, helper.test_data.full_path .. "/")

    assert.equal(table.concat({ "Coverage: 100.0% (1/1 lines)", "  a.lua  100.0% (1/1)", "" }, "\n"), text)
  end)

  it("shows a measured file outside the working directory by its absolute path", function()
    helper.test_data:create_file("inside/keep.lua", "")
    local outside = vim.fs.normalize(helper.test_data:create_file("outside.lua", "return 1"))
    local merged = { [outside] = { max = 1, lines = { [1] = 1 } } }

    local text = report.summary(merged, helper.test_data:path("inside"))

    assert.equal(
      table.concat({ "Coverage: 100.0% (1/1 lines)", ("  %s  100.0%% (1/1)"):format(outside), "" }, "\n"),
      text
    )
  end)

  it("reports n/a when nothing was measured", function()
    local text = report.summary({}, helper.test_data.full_path)

    assert.match("Coverage: n/a", text)
  end)

  it("lists a file whose name is longer than the width string.format accepts", function()
    local too_long_for_a_format_width = ("d"):rep(120) .. ".lua"
    --- @type SummaryLine[]
    local lines = { { code = "return 1", hit = true, coverable = true } }

    local text = summary_of(lines, too_long_for_a_format_width)

    assert.match(file_pattern(too_long_for_a_format_width, lines), text)
  end)
end)
