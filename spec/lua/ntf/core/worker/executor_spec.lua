local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local tree = require("ntf.core.tree")
local executor = require("ntf.core.worker.executor")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending
local before_each, after_each = ntf.before_each, ntf.after_each
local finally = ntf.finally

_G.__NTF_LOG = {}
local log = function(entry)
  table.insert(_G.__NTF_LOG, entry)
end

describe("block", function()
  before_each(function()
    log("before")
  end)
  after_each(function()
    log("after")
  end)

  it("passes", function()
    log("it1")
    finally(function()
      log("finally1")
    end)
  end)

  it("fails", function()
    log("it2")
    error("boom")
  end)

  it("pends", function()
    pending("later")
  end)
end)
]]

describe("ntf.core.worker.executor.run", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports pass / fail / pending statuses", function()
    local root = tree.build(helper.write_spec(source))
    local results = executor.run(root, nil)

    assert.equal(3, #results)
    assert.equal("passed", results[1].status)
    assert.equal("failed", results[2].status)
    assert.equal("pending", results[3].status)
    assert.match("boom", results[2].message)
  end)

  it("reports a build error without a traceback, since its message already carries its own location", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("broken", function()
  error("boom during build")
end)
]]))
    local results = executor.run(root, nil)

    assert.equal(1, #results)
    assert.equal("error", results[1].status)
    assert.is_nil(results[1].traceback)
    assert.match(":%d+:", results[1].message)
  end)

  it("runs before_each/after_each/finally per test", function()
    local root = tree.build(helper.write_spec(source))
    executor.run(root, nil)

    local passing_test = { "before", "it1", "finally1", "after" }
    local failing_test = { "before", "it2", "after" }
    local test_pending_from_inside_its_body = { "before", "after" }

    local log = rawget(_G, "__NTF_LOG")
    assert.same(vim.iter({ passing_test, failing_test, test_pending_from_inside_its_body }):flatten():totable(), log)
  end)

  it("runs only the selected leaf ids", function()
    local root = tree.build(helper.write_spec(source))
    local results = executor.run(root, { ["1.1"] = true })

    assert.equal(1, #results)
    assert.equal("passes", results[1].name)
  end)

  it("traces a failure from the raising frame down, keeping error's own frame at the top", function()
    local root = tree.build(helper.write_spec(source))
    local results = executor.run(root, nil)

    local frames = vim.split(results[2].traceback, "\n", { plain = true })
    assert.equal("stack traceback:", frames[2])
    assert.match("%[C%]: in function 'error'", frames[3])
    assert.match("temp_spec%.lua", frames[4])
  end)

  it("times a test in seconds, from its own start", function()
    local root = tree.build(helper.write_spec(source))
    local results = executor.run(root, nil)

    local a_test_takes_far_under_a_minute = 60
    assert.is_true(results[1].duration >= 0)
    assert.is_true(results[1].duration < a_test_takes_far_under_a_minute)
  end)

  it("inspects an error value that is not a string, rather than handing it on", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("throws a table", function()
  error({ code = 42 })
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.match("code = 42", results[1].message)
  end)

  it("keeps a nil error value nil, rather than inspecting it into text", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("throws nothing", function()
  error()
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.is_nil(results[1].message)
  end)

  it("runs every finally in reverse order of registration", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
_G.__NTF_LOG = {}
ntf.it("registers two", function()
  ntf.finally(function()
    table.insert(_G.__NTF_LOG, "first")
  end)
  ntf.finally(function()
    table.insert(_G.__NTF_LOG, "second")
  end)
end)
]]))
    executor.run(root, nil)

    assert.same({ "second", "first" }, rawget(_G, "__NTF_LOG"))
  end)

  it("reports a declared pending as pending, without running anything", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.pending("not written yet")
]]))
    local results = executor.run(root, nil)

    assert.equal(1, #results)
    assert.equal("pending", results[1].status)
    assert.equal("not written yet", results[1].name)
  end)

  it("runs every before_each of the chain, not only the first", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
_G.__NTF_LOG = {}
ntf.describe("outer", function()
  ntf.before_each(function()
    table.insert(_G.__NTF_LOG, "outer")
  end)
  ntf.describe("inner", function()
    ntf.before_each(function()
      table.insert(_G.__NTF_LOG, "inner")
    end)
    ntf.it("runs", function() end)
  end)
end)
]]))
    executor.run(root, nil)

    assert.same({ "outer", "inner" }, rawget(_G, "__NTF_LOG"))
  end)

  it("reports a test whose before_each errored as an error, naming the hook's failure", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("block", function()
  ntf.before_each(function()
    error("before blew up")
  end)
  ntf.it("never runs its body", function()
    error("the body should not be reached")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("before blew up", results[1].message)
  end)

  it("reports a test whose before_each pended as pending, without running the body", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
_G.__NTF_LOG = {}
ntf.describe("block", function()
  ntf.before_each(function()
    ntf.pending("the fixture is not available here")
  end)
  ntf.after_each(function()
    table.insert(_G.__NTF_LOG, "after")
  end)
  ntf.it("never runs its body", function()
    table.insert(_G.__NTF_LOG, "body")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("pending", results[1].status)
    assert.equal("the fixture is not available here", results[1].message)
    assert.is_nil(results[1].traceback)
    assert.same({ "after" }, rawget(_G, "__NTF_LOG"))
  end)

  it("stops the before_each chain at the hook that pended", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
_G.__NTF_LOG = {}
ntf.describe("outer", function()
  ntf.before_each(function()
    ntf.pending("outer says no")
  end)
  ntf.describe("inner", function()
    ntf.before_each(function()
      table.insert(_G.__NTF_LOG, "inner")
    end)
    ntf.it("never runs", function() end)
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("pending", results[1].status)
    assert.same({}, rawget(_G, "__NTF_LOG"))
  end)

  it("names an after_each pending() as too late, rather than reporting its reason as the error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("block", function()
  ntf.after_each(function()
    ntf.pending("too late to skip")
  end)
  ntf.it("passes", function() end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("pending%(%) once the result is decided", results[1].message)
    assert.is_nil(results[1].traceback)
  end)

  it("names a finally pending() as too late, rather than reporting its reason as the error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("passes", function()
  ntf.finally(function()
    ntf.pending("too late to skip")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("pending%(%) once the result is decided", results[1].message)
    assert.is_nil(results[1].traceback)
  end)

  it("reports a passing test whose after_each errored as an error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("block", function()
  ntf.after_each(function()
    error("after blew up")
  end)
  ntf.it("passes", function() end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("after blew up", results[1].message)
  end)

  it("reports a passing test whose finally errored as an error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("passes", function()
  ntf.finally(function()
    error("finally blew up")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("finally blew up", results[1].message)
    assert.match("temp_spec%.lua", results[1].traceback)
  end)

  it("keeps a failed test failed and reports the after_each that also errored", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("block", function()
  ntf.after_each(function()
    error("after blew up")
  end)
  ntf.it("fails", function()
    error("the body blew up")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.match("the body blew up", results[1].message)
    assert.match("after blew up", results[1].message)
  end)

  it("keeps a failed test failed and reports the finally that also errored", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("fails", function()
  ntf.finally(function()
    error("finally blew up")
  end)
  error("the body blew up")
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.match("the body blew up", results[1].message)
    assert.match("finally blew up", results[1].message)
  end)

  it("reports a pending test whose finally errored as an error, since a pending leaves the run green", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("pends", function()
  ntf.finally(function()
    error("finally blew up")
  end)
  ntf.pending("not here")
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("finally blew up", results[1].message)
  end)

  it("names a finally pending() as too late even where the test already failed", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("fails", function()
  ntf.finally(function()
    ntf.pending("too late to skip")
  end)
  error("the body blew up")
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.match("the body blew up", results[1].message)
    assert.match("pending%(%) once the result is decided", results[1].message)
  end)

  it("reports both teardowns when a finally and an after_each each error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("block", function()
  ntf.after_each(function()
    error("after blew up")
  end)
  ntf.it("passes", function()
    ntf.finally(function()
      error("finally blew up")
    end)
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("error", results[1].status)
    assert.match("finally blew up", results[1].message)
    assert.match("after blew up", results[1].message)
  end)

  it("runs every finally even after one of them errors, and reports the first error", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
_G.__NTF_LOG = {}
ntf.it("registers three", function()
  ntf.finally(function()
    table.insert(_G.__NTF_LOG, "first")
  end)
  ntf.finally(function()
    error("the middle blew up")
  end)
  ntf.finally(function()
    table.insert(_G.__NTF_LOG, "last")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.same({ "last", "first" }, rawget(_G, "__NTF_LOG"))
    assert.equal("error", results[1].status)
    assert.match("the middle blew up", results[1].message)
  end)

  it("keeps a test's own failure when its finally errors too", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.it("fails", function()
  ntf.finally(function()
    error("finally blew up")
  end)
  error("the body blew up")
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.match("the body blew up", results[1].message)
  end)

  it("keeps a test's own failure when its after_each errors too", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("block", function()
  ntf.after_each(function()
    error("after blew up")
  end)
  ntf.it("fails", function()
    error("the body blew up")
  end)
end)
]]))
    local results = executor.run(root, nil)

    assert.equal("failed", results[1].status)
    assert.match("the body blew up", results[1].message)
  end)
end)

local broken_describe_source = [[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("outer", function()
  describe("broken", function()
    it("never reached", function() end)
    error("describe body blew up")
  end)

  it("sibling still runs", function() end)
end)
]]

describe("ntf.core.worker.executor.run describe-body errors", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("reports the errored describe and skips its children, but runs siblings", function()
    local root = tree.build(helper.write_spec(broken_describe_source))
    local results = executor.run(root, nil)

    assert.equal(2, #results)

    local broken = results[1]
    assert.equal("error", broken.status)
    assert.same({ "outer", "broken" }, broken.names)
    assert.match("describe body blew up", broken.message)
    assert.truthy(broken.trace)

    assert.equal("sibling still runs", results[2].name)
    assert.equal("passed", results[2].status)
  end)
end)
