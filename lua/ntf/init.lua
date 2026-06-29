local tree = require("ntf.core.tree")
local builder = require("ntf.assert.builder")

local M = {}

--- @class NtfItOption
--- @field timeout integer? per-process timeout in ms (e.g. `{ timeout = 1000 }`),
---   overriding the `--timeout` default; an exceeded worker is killed and
---   reported as an error.

--- Define a test group. Its body runs at build time to discover nested
--- `describe`/`it`; the body itself is never reported as a test.
--- @param name string: group name
--- @param fn fun() body that declares nested `describe`/`it`
function M.describe(name, fn)
  return tree.describe(name, fn)
end

--- Define a test case. The body runs at execution time, in its own fresh Neovim
--- process. This is not configurable: state never leaks between tests, because
--- no two tests ever share a process.
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

--- Register a callback run when the current test finishes (pass or fail).
--- @param fn fun() callback body
function M.finally(fn)
  return tree.finally(fn)
end

--- @class NtfDecorateCoverageOption
--- @field enable boolean? when `false`, clear the decoration instead of drawing
---   it (default `true`).
--- @field path string? `luacov.stats.out` file to read (default
---   `"./luacov.stats.out"`).
--- @field bufnr integer? target buffer (default `0`, the current buffer).

--- Decorate a buffer's sign column with per-line test coverage read from a
--- `luacov.stats.out` file (as written by `ntf --coverage`): covered lines are
--- marked with the `NtfCoverageCovered` highlight, coverable-but-missed lines
--- with `NtfCoverageMissed`.
--- @param opts NtfDecorateCoverageOption?: |NtfDecorateCoverageOption|
function M.decorate_coverage(opts)
  return require("ntf.core.coverage.decorate").decorate(opts)
end

--- @class NtfIsDecoratedCoverageOption
--- @field bufnr integer? target buffer (default `0`, the current buffer).

--- Whether `decorate_coverage` is currently drawing on the buffer. Intended for
--- a toggle mapping paired with `decorate_coverage`.
--- @param opts NtfIsDecoratedCoverageOption?: |NtfIsDecoratedCoverageOption|
--- @return boolean
function M.is_decorated_coverage(opts)
  return require("ntf.core.coverage.decorate").is_decorated(opts)
end

-- Assertion namespace (`assert.equal`, `assert.same`, `assert.match`, ...).
-- See |ntf-WRITING-SPECS|.
--- @type NtfAssert
M.assert = builder.assert

return M
