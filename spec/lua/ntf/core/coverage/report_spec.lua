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

  it("lists a never-executed file at 0%", function()
    --- @type SummaryLine[]
    local lines = {
      { code = "local function f()", hit = false, coverable = false },
      { code = "  return 1", hit = false, coverable = true },
      { code = "end", hit = false, coverable = false },
      { code = "return f", hit = false, coverable = true },
    }

    local text = summary_of(lines)

    assert.match(file_pattern("mod.lua", lines), text)
  end)

  it("reports n/a when nothing was measured", function()
    local text = report.summary({}, helper.test_data.full_path)

    assert.match("Coverage: n/a", text)
  end)

  it("lists a file whose path is too long for a format width", function()
    local too_long_for_a_format_width = ("d"):rep(120) .. ".lua"
    --- @type SummaryLine[]
    local lines = { { code = "return 1", hit = true, coverable = true } }

    local text = summary_of(lines, too_long_for_a_format_width)

    assert.match(file_pattern(too_long_for_a_format_width, lines), text)
  end)
end)
