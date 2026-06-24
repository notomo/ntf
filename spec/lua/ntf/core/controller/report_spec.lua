local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local report = require("ntf.core.controller.report")

describe("ntf.core.controller.report.build output", function()
  it("labels a whole-file worker by its spec file", function()
    local outputs = {
      { index = 1, file = "spec/a_spec.lua", name = "", output = "hello\nworld\n" },
    }
    local text = report.build({}, {}, { color = false }, outputs)

    assert.match("OUTPUT spec/a_spec.lua", text)
    assert.match("    hello", text)
    assert.match("    world", text)
  end)

  it("labels a single-test worker by its full name, with the file dim below", function()
    local outputs = {
      { index = 1, file = "spec/a_spec.lua", name = "group adds", output = "noise\n" },
    }
    local text = report.build({}, {}, { color = false }, outputs)

    assert.match("OUTPUT group adds", text)
    assert.match("spec/a_spec.lua", text)
    assert.match("    noise", text)
  end)

  it("renders one block per worker in the given order", function()
    local outputs = {
      { index = 1, file = "spec/a_spec.lua", name = "", output = "from a\n" },
      { index = 2, file = "spec/b_spec.lua", name = "", output = "from b\n" },
    }
    local text = report.build({}, {}, { color = false }, outputs)

    assert.match("OUTPUT spec/a_spec.lua", text)
    assert.match("OUTPUT spec/b_spec.lua", text)
    assert.is_true(text:find("from a", 1, true) < text:find("from b", 1, true))
  end)

  it("adds nothing when no worker emitted output", function()
    local results = {
      { status = "passed", names = { "block", "quiet" } },
    }
    local text = report.build(results, {}, { color = false }, {})

    assert.no.match("OUTPUT", text)
  end)
end)
