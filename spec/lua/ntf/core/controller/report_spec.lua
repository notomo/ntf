local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local report = require("ntf.core.controller.report")

describe("ntf.core.controller.report.output_block", function()
  it("labels a whole-file worker by its spec file", function()
    local out = { file = "spec/a_spec.lua", name = "", output = "hello\nworld\n" }
    local text = report.output_block(out, false)

    assert.match("OUTPUT spec/a_spec.lua", text)
    assert.match("\nhello", text)
    assert.match("\nworld", text)
  end)

  it("labels a single-test worker by its file followed by its full name", function()
    local out = { file = "spec/a_spec.lua", name = "group adds", output = "noise\n" }
    local text = report.output_block(out, false)

    assert.match("OUTPUT spec/a_spec.lua group adds", text)
    assert.match("\nnoise", text)
  end)
end)

describe("ntf.core.controller.report.build", function()
  it("never emits OUTPUT itself; captured output is streamed live instead", function()
    local results = {
      { status = "passed", names = { "block", "quiet" } },
    }
    local text = report.build(results, {}, { color = false })

    assert.no.match("OUTPUT", text)
  end)
end)
