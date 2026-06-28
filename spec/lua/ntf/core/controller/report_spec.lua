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

  it("summarizes a clean run as all passed with exit code 0", function()
    local results = {
      { status = "passed", names = { "a" } },
      { status = "passed", names = { "b" } },
    }
    local text, code = report.build(results, {}, { color = false })

    assert.match("2 tests: 2 passed", text)
    assert.no.match("failed", text)
    assert.no.match("pending", text)
    assert.equal(0, code)
  end)

  it("counts failed, errors and pending alongside passed", function()
    local results = {
      { status = "passed", names = { "a" } },
      { status = "failed", names = { "b" }, message = "nope" },
      { status = "error", names = { "c" }, message = "boom" },
      { status = "pending", names = { "d" } },
    }
    local text, code = report.build(results, {}, { color = false })

    assert.match("4 tests:", text)
    assert.match("1 passed", text)
    assert.match("1 failed", text)
    assert.match("1 errors", text)
    assert.match("1 pending", text)
    assert.equal(1, code)
  end)

  it("renders a failed result as FAIL with its full name, source and message", function()
    local results = {
      {
        status = "failed",
        names = { "math", "adds" },
        message = "expected 3 but got 4",
        trace = { source = "@spec/math_spec.lua", line = 12 },
      },
    }
    local text, code = report.build(results, {}, { color = false })

    assert.match("FAIL math adds", text)
    assert.match("spec/math_spec.lua:12", text)
    assert.match("expected 3 but got 4", text)
    assert.equal(1, code)
  end)

  it("renders an errored result as ERROR", function()
    local results = {
      { status = "error", names = { "broken" }, message = "runtime kaboom" },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("ERROR broken", text)
    assert.match("runtime kaboom", text)
  end)

  it("shows '?' as the source when a problem has no trace", function()
    local results = {
      { status = "failed", names = { "no trace" }, message = "x" },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("\n  %?", text)
  end)

  it("includes a traceback with ntf's own frames stripped out", function()
    local traceback = table.concat({
      "stack traceback:",
      "\t/path/to/lua/ntf/core/worker/executor.lua:1: in function 'run'",
      "\tspec/math_spec.lua:12: in function <spec/math_spec.lua:11>",
      "\t[C]: in function 'xpcall'",
    }, "\n")
    local results = {
      { status = "failed", names = { "math" }, message = "boom", traceback = traceback },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("spec/math_spec.lua:12", text)
    assert.no.match("/lua/ntf/", text)
    assert.no.match("xpcall", text)
  end)

  it("omits the traceback when only its header would survive cleaning", function()
    local traceback = table.concat({
      "stack traceback:",
      "\t/path/to/lua/ntf/core/worker/executor.lua:1: in function 'run'",
    }, "\n")
    local results = {
      { status = "failed", names = { "math" }, message = "boom", traceback = traceback },
    }
    local text = report.build(results, {}, { color = false })

    assert.no.match("traceback", text)
  end)

  it("renders load errors and forces exit code 1 even with no test problems", function()
    local results = {
      { status = "passed", names = { "a" } },
    }
    local load_errors = {
      { file = "spec/broken_spec.lua", message = "syntax error near 'end'" },
    }
    local text, code = report.build(results, load_errors, { color = false })

    assert.match("LOAD ERROR spec/broken_spec.lua", text)
    assert.match("syntax error near 'end'", text)
    assert.equal(1, code)
  end)

  it("falls back to result.name when names is absent", function()
    local results = {
      { status = "failed", name = "solo", message = "x" },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("FAIL solo", text)
  end)

  it("appends the seed line only when shuffling with a seed", function()
    local results = { { status = "passed", names = { "a" } } }

    local shuffled = report.build(results, {}, { color = false, shuffle = true, seed = 42 })
    assert.match("seed: 42", shuffled)

    local plain = report.build(results, {}, { color = false })
    assert.no.match("seed:", plain)
  end)

  it("wraps output in ANSI color codes when color is enabled", function()
    local results = {
      { status = "failed", names = { "a" }, message = "x" },
    }
    local text = report.build(results, {}, { color = true })

    assert.match("\27%[", text)
  end)
end)
