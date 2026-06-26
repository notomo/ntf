local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local report = require("ntf.core.controller.report")

describe("ntf.core.controller.report.output_block", function()
  it("labels a whole-file worker by its spec file", function()
    local out = { file = "spec/a_spec.lua", name = "", output = "hello\nworld\n" }
    local text = report.output_block(out, false)

    assert.match("OUTPUT spec/a_spec.lua", text)
    assert.match("    hello", text)
    assert.match("    world", text)
  end)

  it("labels a single-test worker by its full name, with the file dim below", function()
    local out = { file = "spec/a_spec.lua", name = "group adds", output = "noise\n" }
    local text = report.output_block(out, false)

    assert.match("OUTPUT group adds", text)
    assert.match("spec/a_spec.lua", text)
    assert.match("    noise", text)
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
