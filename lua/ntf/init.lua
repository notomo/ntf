local tree = require("ntf.core.tree")

local M = {}

--- @class NtfItOption
--- @field timeout integer? per-process timeout in ms; see |ntf-TIMEOUT|

--- Define a test group. Its body runs at build time to discover nested
--- `describe`/`it`; the body itself is never reported as a test.
--- @param name string: group name
--- @param fn fun() body that declares nested `describe`/`it`
function M.describe(name, fn)
  return tree.describe(name, fn)
end

--- Define a test case. The body runs at execution time.
--- @param name string: test name
--- @param fn fun() test body
--- @param opts NtfItOption?: |NtfItOption|
function M.it(name, fn, opts)
  return tree.it(name, fn, opts)
end

--- Mark a test as pending. As a declaration it records a skipped node; called
--- inside a running test body it aborts the test as pending.
--- @param name string: pending reason
--- @param fn fun()?: optional body (ignored; pending is never executed)
function M.pending(name, fn)
  return tree.pending(name, fn)
end

--- Register a hook run before each test in the current group.
--- @param fn fun() hook body
function M.before_each(fn)
  return tree.before_each(fn)
end

--- Register a hook run after each test in the current group.
--- @param fn fun() hook body
function M.after_each(fn)
  return tree.after_each(fn)
end

--- Register a hook run once before the current group's tests.
--- @param fn fun() hook body
function M.setup(fn)
  return tree.setup(fn)
end

--- Register a hook run once after the current group's tests.
--- @param fn fun() hook body
function M.teardown(fn)
  return tree.teardown(fn)
end

--- Register a callback run when the current test finishes (pass or fail).
--- @param fn fun() callback body
function M.finally(fn)
  return tree.finally(fn)
end

-- Assertion namespace (`assert.equal`, `assert.same`, `assert.match`, ...).
-- See |ntf-WRITING-SPECS|.
M.assert = tree.assert

return M
