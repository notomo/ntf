local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local report = require("ntf.core.report")

describe("ntf.core.report.build output", function()
  it("renders a passing test's captured output under its full name", function()
    local results = {
      { status = "passed", names = { "block", "prints" }, output = "hello\nworld\n" },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("OUTPUT block prints", text)
    assert.match("    hello", text)
    assert.match("    world", text)
  end)

  it("renders a failing test's output inside its failure block", function()
    local results = {
      {
        status = "failed",
        names = { "block", "boom" },
        message = "kaboom",
        output = "before boom\n",
      },
    }
    local text = report.build(results, {}, { color = false })

    -- output stays attached to the FAIL block, not a separate OUTPUT block
    assert.match("FAIL block boom", text)
    assert.match("output:", text)
    assert.match("before boom", text)
    assert.no.match("OUTPUT block boom", text)
  end)

  it("adds nothing for a test without captured output", function()
    local results = {
      { status = "passed", names = { "block", "quiet" } },
    }
    local text = report.build(results, {}, { color = false })

    assert.no.match("OUTPUT", text)
    assert.no.match("output:", text)
  end)
end)
