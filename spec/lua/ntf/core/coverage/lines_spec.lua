local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local lines = require("ntf.core.coverage.lines")

describe("ntf.core.coverage.lines.coverable", function()
  it("keeps a return of a plain binary expression coverable", function()
    local src = table.concat({
      "local function f(a, b)",
      "  return a + b",
      "end",
    }, "\n")

    assert.is_true(lines.coverable(src)[2])
  end)

  it("does not count a line whose only values are closures", function()
    local src = table.concat({
      "local x",
      "x = nil or function()",
      "  return 1",
      "end",
    }, "\n")

    assert.is_nil(lines.coverable(src)[2])
  end)
end)
