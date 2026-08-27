local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local tree = require("ntf.core.tree")
local helper = require("ntf.test.helper")

local source = [[
local ntf = require("ntf")
local describe, it, pending = ntf.describe, ntf.it, ntf.pending

describe("outer", function()
  it("one", function() end)
  pending("pending two")
  describe("inner", function()
    it("three", function() end)
  end)
  it("quick four", function() end, { timeout = 1000 })
end)
]]

describe("ntf.core.tree.build", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("builds nodes with stable index-path ids", function()
    local root = tree.build(helper.write_spec(source))

    local outer = root.children[1]
    assert.equal("outer", outer.name)
    assert.equal("1", outer.id)
    assert.equal("1.1", outer.children[1].id)
    assert.equal("one", outer.children[1].name)
    assert.equal("1.3", outer.children[3].id)
    assert.equal("inner", outer.children[3].name)
    assert.equal("1.3.1", outer.children[3].children[1].id)
  end)

  it("marks explicit pending() as a pending node", function()
    local root = tree.build(helper.write_spec(source))
    local pending_node = root.children[1].children[2]
    assert.equal("pending", pending_node.type)
    assert.equal("pending two", pending_node.name)
  end)

  it("records the line a body-less pending() was declared on", function()
    local path = helper.write_spec(source)
    local root = tree.build(path)
    local pending_node = root.children[1].children[2]
    assert.equal("@" .. path, pending_node.trace.source)
    assert.equal(6, pending_node.trace.line)
  end)

  it("records the line a describe and an it were defined on", function()
    local root = tree.build(helper.write_spec(source))

    local outer = root.children[1]
    assert.equal(4, outer.trace.line)
    assert.equal(5, outer.children[1].trace.line)
  end)

  it("traces a describe to its function's definition line, not the call site", function()
    local root = tree.build(helper.write_spec(table.concat({
      "local ntf = require('ntf')",
      "local body = function() end",
      "ntf.describe('outer', body)",
    }, "\n")))

    assert.equal(2, root.children[1].trace.line)
  end)

  it("records an it-level timeout opt-in", function()
    local root = tree.build(helper.write_spec(source))
    local timed_it = root.children[1].children[4]
    assert.equal("quick four", timed_it.name)
    assert.equal(1000, timed_it.timeout)
  end)

  it("captures load errors instead of throwing", function()
    local root = tree.build(helper.write_spec([[error("intentionally broken")]]))
    assert.truthy(root.load_error)
  end)

  it("captures a syntax error that keeps the file from even loading", function()
    local root = tree.build(helper.write_spec([[describe((]]))

    -- WHY: a `path:line:` prefix is the loadfile parse error, proving the build
    -- reported that rather than falling through to run the nil chunk.
    -- NOT: asserting only that some load_error is present, which a later
    -- "attempt to call a nil value" would satisfy just as well.
    assert.match(":%d+:", tostring(root.load_error))
    assert.same({}, root.children)
  end)

  it("captures an error thrown inside a describe body on that describe node", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
local describe, it = ntf.describe, ntf.it

describe("outer", function()
  it("one", function() end)
  error("broken describe body")
end)
]]))

    assert.is_nil(root.load_error)
    local outer = root.children[1]
    assert.match("broken describe body", tostring(outer.load_error))
  end)
end)

describe("ntf.core.tree.pending", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("signals a pending() that has no node to attach to with a table, which lua never prefixes", function()
    local ok, thrown = pcall(tree.pending, "outside any describe")

    assert.is_false(ok)
    assert.equal("outside any describe", thrown.message)
    assert.is_true(thrown[tree.PENDING])
  end)

  it("signals it too after a build whose file would not compile, which leaves a stack behind if unwound", function()
    tree.build(helper.write_spec([[describe((]]))

    local ok, thrown = pcall(tree.pending, "outside any describe")

    assert.is_false(ok)
    assert.is_true(thrown[tree.PENDING])
  end)
end)

describe("ntf.core.tree.collect_finallies", function()
  it("gives back only the callbacks of the run it wraps", function()
    local outer_fn, inner_fn = function() end, function() end

    local collected
    local outer = tree.collect_finallies(function()
      collected = tree.collect_finallies(function()
        tree.finally(inner_fn)
      end)
      tree.finally(outer_fn)
    end)

    assert.same({ inner_fn }, collected)
    assert.same({ outer_fn }, outer)
  end)

  it("puts the collector it was given back, so a finally after it lands in that one", function()
    local outer_fn = function() end

    local outer = tree.collect_finallies(function()
      local inner = tree.collect_finallies(function() end)
      assert.same({}, inner)
      tree.finally(outer_fn)
    end)

    assert.same({ outer_fn }, outer)
  end)
end)

describe("ntf.core.tree declaration outside a spec file being loaded", function()
  local declares_from_a_running_test = {
    {
      what = "describe",
      declare = function()
        tree.describe("too late", function() end)
      end,
    },
    {
      what = "it",
      declare = function()
        tree.it("too late", function() end)
      end,
    },
    {
      what = "before_each",
      declare = function()
        tree.before_each(function() end)
      end,
    },
    {
      what = "after_each",
      declare = function()
        tree.after_each(function() end)
      end,
    },
  }

  for _, case in ipairs(declares_from_a_running_test) do
    local what, declare = case.what, case.declare
    it(("raises for a %s() a running test declares"):format(what), function()
      local ok, err = pcall(declare)

      assert.is_false(ok)
      assert.equal(
        ("%s() outside a spec file being loaded: the tests are declared once, before any of them runs"):format(what),
        err
      )
    end)
  end

  it("keeps pending() as the pending signal it already answers with", function()
    local ok, err = pcall(tree.pending, "no node to attach to")

    assert.is_false(ok)
    assert.is_true(err[tree.PENDING])
    assert.equal("no node to attach to", err.message)
  end)
end)

describe("ntf.core.tree.collect_finally", function()
  it("adds the callback to the collector it is given", function()
    local fn = function() end
    local collector = {}

    tree.collect_finally(collector, fn)

    assert.same({ fn }, collector)
  end)

  it("raises for a finally that has no running test to register with", function()
    local ok, err = pcall(tree.collect_finally, nil, function() end)

    assert.is_false(ok)
    assert.equal(
      "finally() outside a running test: only a before_each or a test body registers one, since an after_each already runs after the callbacks",
      err
    )
  end)
end)

describe("ntf.core.tree.full_name", function()
  it("joins names with a space, dropping empty segments", function()
    assert.equal("outer inner three", tree.full_name({ "outer", "", "inner", "three" }))
    assert.equal("", tree.full_name({}))
  end)
end)

describe("ntf.core.tree.is_leaf", function()
  it("treats it and pending as leaves", function()
    assert.is_true(tree.is_leaf({ type = "it" }))
    assert.is_true(tree.is_leaf({ type = "pending" }))
  end)

  it("treats a healthy describe as a non-leaf", function()
    assert.is_false(tree.is_leaf({ type = "describe" }))
  end)

  it("treats a describe whose body errored as a leaf, rather than running the arbitrary prefix it collected", function()
    assert.is_true(tree.is_leaf({ type = "describe", load_error = "boom" }))
  end)
end)

describe("ntf.core.tree.shared_names", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("finds nothing when every leaf carries its own full name", function()
    local root = tree.build(helper.write_spec(source))

    assert.same({}, tree.shared_names(root))
  end)

  it("gathers every declaration site a shared name has, not only the first two", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("case", function() end)
  ntf.it("case", function() end)
  ntf.it("case", function() end)
end)
]]))

    local shared = tree.shared_names(root)

    assert.equal(1, #shared)
    assert.equal("g case", shared[1].name)
    assert.same(
      { 3, 4, 5 },
      vim.tbl_map(function(trace)
        return trace.line
      end, shared[1].traces)
    )
  end)

  it("answers for every shared name at once, first occurrence first", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("first", function() end)
  ntf.it("second", function() end)
  ntf.it("second", function() end)
  ntf.it("first", function() end)
end)
]]))

    local shared = tree.shared_names(root)

    assert.same(
      { "g first", "g second" },
      vim.tbl_map(function(entry)
        return entry.name
      end, shared)
    )
  end)

  it("takes the same name under two describes as two full names", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("ok", function() end)
end)
ntf.describe("other", function()
  ntf.it("ok", function() end)
end)
]]))

    assert.same({}, tree.shared_names(root))
  end)

  it("takes two names that differ only in whitespace as one, since that is all a reader sees", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("a b", function() end)
  ntf.it("a\nb", function() end)
end)
]]))

    assert.equal("g a b", tree.shared_names(root)[1].name)
  end)

  it("takes a pending as a leaf that has to carry its own name too", function()
    local root = tree.build(helper.write_spec([[
local ntf = require("ntf")
ntf.describe("g", function()
  ntf.it("same name", function() end)
  ntf.pending("same name")
end)
]]))

    assert.equal("g same name", tree.shared_names(root)[1].name)
  end)
end)

describe("ntf.core.tree.one_line", function()
  it("folds every run of whitespace into one space, newlines included", function()
    assert.equal("select ( hoge foo ) on ( hoge )", tree.one_line("select (\nhoge\nfoo\n) on (\thoge  )"))
  end)

  it("leaves a name that already sits on one line alone", function()
    assert.equal("group adds", tree.one_line("group adds"))
  end)
end)

local function tree_of(leaves)
  local lines = { 'local ntf = require("ntf")', 'ntf.describe("g", function()' }
  for _, name in ipairs(leaves) do
    table.insert(lines, ("  ntf.it(%q, function() end)"):format(name))
  end
  table.insert(lines, "end)")
  return tree.build(helper.write_spec(table.concat(lines, "\n")))
end

describe("ntf.core.tree.leaf_name", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("answers with the folded name of the leaf holding the id", function()
    local root = tree_of({ "a", "b", "c" })

    assert.equal("g b", tree.leaf_name(root, "1.2"))
  end)

  it("answers with nothing for an id the tree does not hold", function()
    local root = tree_of({ "a" })

    assert.is_nil(tree.leaf_name(root, "1.2"))
  end)
end)

describe("ntf.core.tree.leaf_count", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("counts every leaf the file declares", function()
    assert.equal(3, tree.leaf_count(tree_of({ "a", "b", "c" })))
  end)
end)

describe("ntf.core.tree.divergence", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("finds nothing when this process declares the tree the run planned from", function()
    local root = tree_of({ "a", "b" })

    assert.is_nil(tree.divergence(root, "1.2", { "g", "b" }, 2))
  end)

  it("names what the position holds when another test took it", function()
    local root = tree_of({ "extra", "a", "b" })

    local message = tree.divergence(root, "1.2", { "g", "b" }, 2)

    assert.match('the run picked "g b"', message)
    assert.match('this position holds "g a"', message)
  end)

  it("says the position holds no test when the tree lost it", function()
    local root = tree_of({ "a" })

    local message = tree.divergence(root, "1.2", { "g", "b" }, 2)

    assert.match("this position holds no test", message)
  end)

  it("counts the leaves when the position still holds the planned test, since a later one leaves it alone", function()
    local root = tree_of({ "a", "b", "grown" })

    local message = tree.divergence(root, "1.2", { "g", "b" }, 2)

    assert.match('this position still holds "g b"', message)
    assert.match("the run planned 2 tests from this file and this process declares 3", message)
  end)
end)
