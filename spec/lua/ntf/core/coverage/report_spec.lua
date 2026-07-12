local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local report = require("ntf.core.coverage.report")
local helper = require("ntf.test.helper")

describe("ntf.core.coverage.report.summary", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports covered/coverable percentages from source and hits", function()
    local src = helper.test_data:create_file(
      "mod.lua",
      table.concat({
        "local function f(x)", -- 1 code, hit
        "  -- comment", -- 2 not code
        "  if x then", -- 3 code, hit
        "    return 1", -- 4 code, missed
        "  end", -- 5 lone end, not code
        "  return 0", -- 6 code, hit
        "end", -- 7 lone end, not code
      }, "\n")
    )
    local merged = { [vim.fs.normalize(src)] = { max = 6, lines = { [1] = 1, [3] = 1, [6] = 1 } } }

    local text = report.summary(merged, helper.test_data.full_path)

    -- coverable code lines = {1,3,4,6}; covered (hit) = {1,3,6} -> 3/4 = 75%.
    assert.match("Coverage: 75.0%% %(3/4 lines%)", text)
    assert.match("mod.lua%s+75.0%% %(3/4%)", text)
  end)

  it("excludes table fields and opener braces from the denominator", function()
    local src = helper.test_data:create_file(
      "mod.lua",
      table.concat({
        "local t1 = {", -- 1 code, hit
        '  one = "one",', -- 2 field, not coverable
        '  two = "two",', -- 3 field, not coverable
        "}", -- 4 lone close, not coverable
        "local t2 = {", -- 5 code, hit
        "  f(),", -- 6 call, coverable, missed
        "}", -- 7 lone close, not coverable
        "return t1", -- 8 code, hit
      }, "\n")
    )
    local merged = { [vim.fs.normalize(src)] = { max = 8, lines = { [1] = 1, [5] = 1, [8] = 1 } } }

    local text = report.summary(merged, helper.test_data.full_path)

    -- coverable lines = {1,5,6,8}; covered = {1,5,8} -> 3/4 = 75%. The fields and
    -- braces (2,3,4,7) must not inflate the denominator.
    assert.match("Coverage: 75.0%% %(3/4 lines%)", text)
  end)

  it("lists a never-executed file at 0%", function()
    local src = helper.test_data:create_file(
      "mod.lua",
      table.concat({
        "local function f()",
        "  return 1",
        "end",
        "return f",
      }, "\n")
    )
    local merged = { [vim.fs.normalize(src)] = { max = 0, lines = {} } }

    local text = report.summary(merged, helper.test_data.full_path)

    assert.match("mod.lua%s+0.0%% %(0/2%)", text)
  end)

  it("reports n/a when nothing was measured", function()
    local text = report.summary({}, helper.test_data.full_path)

    assert.match("Coverage: n/a", text)
  end)

  it("lists a file whose path is too long for a format width", function()
    -- `string.format` rejects a width beyond 99, which a deep enough path would
    -- otherwise reach.
    local name = ("d"):rep(120) .. ".lua"
    local src = helper.test_data:create_file(name, "return 1")
    local merged = { [vim.fs.normalize(src)] = { max = 1, lines = { [1] = 1 } } }

    local text = report.summary(merged, helper.test_data.full_path)

    assert.match(name .. "%s+100.0%% %(1/1%)", text)
  end)
end)
