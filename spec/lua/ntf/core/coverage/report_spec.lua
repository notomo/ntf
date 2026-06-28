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
    assert.match("mod.lua%s+75.0%%", text)
  end)

  it("reports n/a when nothing was measured", function()
    local text = report.summary({}, helper.test_data.full_path)

    assert.match("Coverage: n/a", text)
  end)
end)
