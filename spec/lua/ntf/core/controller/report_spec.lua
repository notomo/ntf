local ntf = require("ntf")
local describe, it, finally, assert = ntf.describe, ntf.it, ntf.finally, ntf.assert
local report = require("ntf.core.controller.report")

describe("ntf.core.controller.report.output_block", function()
  it("labels output only by its file when the scope has no name", function()
    local out = { file = "spec/a_spec.lua", name = "", output = "hello\nworld\n" }
    local text = report.output_block(out, false)

    assert.equal("OUTPUT spec/a_spec.lua\nhello\nworld\n\n", text)
  end)

  it("paints the header dim and the name bold when color is enabled", function()
    local out = { file = "spec/a_spec.lua", name = "group adds", output = "noise\n" }

    local text = report.output_block(out, true)

    local dim, bold, reset = "\27[90m", "\27[1m", "\27[0m"
    assert.equal(
      ("%sOUTPUT %s%sspec/a_spec.lua%s %sgroup adds%s\nnoise\n\n"):format(dim, reset, dim, reset, bold, reset),
      text
    )
  end)

  it("labels a single-test worker by its file followed by its full name", function()
    local out = { file = "spec/a_spec.lua", name = "group adds", output = "noise\n" }
    local text = report.output_block(out, false)

    assert.match("OUTPUT spec/a_spec.lua group adds", text)
    assert.match("\nnoise", text)
  end)

  it(
    "ends the block with a blank separator line, since it is streamed live and no later pass can space it out",
    function()
      local out = { file = "spec/a_spec.lua", name = "", output = "hello\n" }

      local text = report.output_block(out, false)

      assert.equal("\n\n", text:sub(-2))
    end
  )

  it("builds the block from a fast event context, where a Vimscript getcwd() would be forbidden", function()
    local out = { file = "spec/a_spec.lua", name = "", output = "hello\n" }

    local text, err
    local timer = assert(vim.uv.new_timer())
    timer:start(0, 0, function()
      local ok, result = pcall(report.output_block, out, false)
      if ok then
        text = result
      else
        err = result
      end
      timer:stop()
      timer:close()
    end)
    vim.wait(2000, function()
      return text ~= nil or err ~= nil
    end)

    assert.is_nil(err)
    assert.match("OUTPUT spec/a_spec.lua", text)
  end)
end)

describe("ntf.core.controller.report.reported_error", function()
  it("carries its message where the traceback handler of a catch-all hands it back undecorated", function()
    local ok, err = xpcall(function()
      error(report.reported_error("the run gave up after 1.0s"), 0)
    end, debug.traceback)

    assert.is_false(ok)
    assert.equal("the run gave up after 1.0s", report.error_message(err))
  end)
end)

describe("ntf.core.controller.report.error_message", function()
  it("prints a raise that carries no message of its own as it is", function()
    assert.equal("spec/a_spec.lua:3: boom", report.error_message("spec/a_spec.lua:3: boom"))
  end)

  it("prints a table raise that names no message as it is, rather than as its own message", function()
    assert.match("^table: ", report.error_message({ mistaken = "for a reported error" }))
  end)
end)

describe("ntf.core.controller.report.build", function()
  it("keeps a name spelled over several lines on the FAIL heading line", function()
    local results = {
      {
        id = "1",
        names = { "group", "fails (\na\n)" },
        status = "failed",
        message = "boom",
        trace = { source = "@spec/a_spec.lua", line = 3 },
      },
    }

    local text = report.build(results, {}, { color = false })

    assert.match("FAIL group fails %(\\na\\n%)\n", text)
  end)

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

    assert.equal("2 tests: 2 passed\n", text)
    assert.equal(0, code)
  end)

  it("counts the tests a run that gave up never heard from, so its count line stays the planned one", function()
    local results = {
      { status = "passed", names = { "a" } },
    }
    local gave_up = {
      budget = 900000,
      unfinished = 2,
      total = 3,
      unit = "tests",
      launched = { "spec/a_spec.lua:3 a hangs" },
    }

    local text, code = report.build(results, {}, { color = false, gave_up = gave_up })

    assert.equal(
      "GAVE UP after 900.0s: 2 of 3 tests never reported back, 1 of them from a worker it had launched:\n"
        .. "  spec/a_spec.lua:3 a hangs\n"
        .. "\n"
        .. "3 tests: 1 passed  2 never reported back\n",
      text
    )
    assert.equal(1, code)
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
    local text, code = report.build(results, {}, { color = false })

    assert.match("ERROR broken", text)
    assert.match("runtime kaboom", text)
    assert.equal(1, code)
  end)

  it("renders a problem that carries no message without a blank message line", function()
    local results = {
      { status = "error", names = { "broken" }, trace = { source = "@spec/x_spec.lua", line = 3 } },
    }

    local text = report.build(results, {}, { color = false })

    assert.equal(
      table.concat({ "ERROR broken", "  spec/x_spec.lua:3", "", "1 tests: 0 passed  1 errors", "" }, "\n"),
      text
    )
  end)

  it("shows '?' as the source when a problem has no trace", function()
    local results = {
      { status = "failed", names = { "no trace" }, message = "x" },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("\n  %?", text)
  end)

  it("shows only the source when a trace has no line", function()
    local results = {
      { status = "failed", names = { "no line" }, message = "x", trace = { source = "@spec/x_spec.lua" } },
    }
    local text = report.build(results, {}, { color = false })

    assert.match("spec/x_spec%.lua", text)
    assert.no.match("x_spec%.lua:", text)
  end)

  it("normalizes a source before stripping the working directory off it", function()
    local results = {
      {
        status = "failed",
        names = { "unnormalized" },
        message = "x",
        trace = { source = "@" .. vim.fn.getcwd() .. "//spec/./x_spec.lua", line = 1 },
      },
    }

    local text = report.build(results, {}, { color = false })

    assert.match("\n  spec/x_spec%.lua:1", text)
  end)

  it("keeps the source of a sibling directory whose name merely starts with the working directory's", function()
    local sibling = require("ntf.core.path").normalize(vim.fn.getcwd()) .. "-other"
    local results = {
      {
        status = "failed",
        names = { "sibling" },
        message = "x",
        trace = { source = "@" .. sibling .. "/spec/x_spec.lua", line = 1 },
      },
    }

    local text = report.build(results, {}, { color = false })

    assert.match(vim.pesc(sibling .. "/spec/x_spec.lua:1"), text)
  end)

  it("renders with no load errors given, which the caller may leave out", function()
    local results = {
      { status = "passed", names = { "a" } },
    }

    local text, code = report.build(results, nil, { color = false })

    assert.match("1 passed", text)
    assert.equal(0, code)
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

  it("drops the frames the worker launcher leaves under the test's own", function()
    local traceback = table.concat({
      "stack traceback:",
      "\tspec/math_spec.lua:12: in function <spec/math_spec.lua:11>",
      "\t[C]: in function 'luafile'",
      '\t[string ":lua"]:1: in main chunk',
    }, "\n")
    local results = {
      { status = "failed", names = { "math" }, message = "boom", traceback = traceback },
    }

    local text = report.build(results, {}, { color = false })

    assert.match("spec/math_spec.lua:12", text)
    assert.no.match("luafile", text)
    assert.no.match("in main chunk", text)
  end)

  it("drops an ntf, xpcall or error frame that starts at the line's very first byte", function()
    local traceback = table.concat({
      "stack traceback:",
      "/lua/ntf/core/worker/executor.lua:1: in function 'run'",
      "in function 'xpcall'",
      "in function 'error'",
      "\tspec/math_spec.lua:12: in function <spec/math_spec.lua:11>",
    }, "\n")
    local results = {
      { status = "failed", names = { "math" }, message = "boom", traceback = traceback },
    }

    local text = report.build(results, {}, { color = false })

    assert.match("spec/math_spec.lua:12", text)
    assert.no.match("/lua/ntf/", text)
    assert.no.match("xpcall", text)
    assert.no.match("in function 'error'", text)
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

  it("wraps output in ANSI color codes when color is enabled", function()
    local results = {
      { status = "failed", names = { "a" }, message = "x" },
    }
    local text = report.build(results, {}, { color = true })

    assert.match("\27%[", text)
  end)
end)

describe("ntf.core.controller.report.load_error_block", function()
  it("ends every block with a blank separator line", function()
    local block = report.load_error_block(
      { file = "spec/broken_spec.lua", message = "syntax error near 'end'" },
      report.painter(false)
    )

    assert.equal("", block[#block])
  end)
end)

describe("ntf.core.controller.report.resolve_color", function()
  local function fake_tty()
    local saved = vim.uv.guess_handle
    finally(function()
      vim.uv.guess_handle = saved
    end)
    vim.uv.guess_handle = function(fd)
      return fd == 1 and "tty" or "pipe"
    end
  end

  it("is false when stdout is not a tty, as under the test runner where it is a pipe", function()
    assert.is_false(report.resolve_color())
  end)

  it("is true on a tty when NO_COLOR is unset", function()
    fake_tty()
    vim.env.NO_COLOR = nil

    assert.is_true(report.resolve_color())
  end)

  it("is false when NO_COLOR is set even on a tty", function()
    fake_tty()
    vim.env.NO_COLOR = "1"

    assert.is_false(report.resolve_color())
  end)
end)

describe("ntf.core.controller.report.duration", function()
  it("shows a second and over in seconds", function()
    assert.equal("4.6s", report.duration(4.62))
  end)

  it("shows a whole second in seconds, the unit changing only below one", function()
    assert.equal("1.0s", report.duration(1.0))
  end)

  it("shows the millisecond a run just short of a second took, rather than rounding it to a second", function()
    assert.equal("999ms", report.duration(0.999))
  end)

  it("shows a fraction of a second in milliseconds, which one decimal of seconds would flatten to zero", function()
    assert.equal("43ms", report.duration(0.0432))
  end)
end)

describe("ntf.core.controller.report.timing", function()
  it("splits the time the workers spent into the startup each test pays and the time in the tests", function()
    local results = {
      { id = "1", names = { "x", "one" }, status = "passed", duration = 0.5 },
      { id = "2", names = { "x", "two" }, status = "passed", duration = 1.5 },
    }

    local text = report.timing(results, { elapsed = 3.0, worker = 6.0, jobs = 4 })

    assert.equal(
      table.concat({
        "Time: 3.0s elapsed, 4 jobs",
        "  nvim startup: 2.0s avg per test",
        "  test execution: 2.0s total",
        "",
      }, "\n"),
      text
    )
  end)

  it("keeps a short run readable, where a tenth of a second is coarser than the whole run", function()
    local results = {
      { id = "1", names = { "x", "one" }, status = "passed", duration = 0.012 },
      { id = "2", names = { "x", "two" }, status = "passed", duration = 0.008 },
    }

    local text = report.timing(results, { elapsed = 0.043, worker = 0.054, jobs = 8 })

    assert.equal(
      table.concat({
        "Time: 43ms elapsed, 8 jobs",
        "  nvim startup: 17ms avg per test",
        "  test execution: 20ms total",
        "",
      }, "\n"),
      text
    )
  end)

  it("reports the elapsed time alone when no test ran, having no test to average over", function()
    local text = report.timing({}, { elapsed = 1.5, worker = 0, jobs = 2 })

    assert.equal("Time: 1.5s elapsed, 2 jobs\n", text)
  end)

  it("counts the whole life of a worker that reported no duration as startup", function()
    local results = { { id = "1", names = { "x", "one" }, status = "error" } }

    local text = report.timing(results, { elapsed = 2.0, worker = 2.0, jobs = 1 })

    assert.match("nvim startup: 2%.0s avg per test", text)
    assert.match("test execution: 0ms total", text)
  end)
end)
