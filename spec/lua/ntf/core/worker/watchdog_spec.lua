local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local watchdog = require("ntf.core.worker.watchdog")
local helper = require("ntf.test.helper")

describe("ntf.core.worker.watchdog.deadline", function()
  it("outlives the timeout the run would kill the worker at", function()
    assert.equal(31000, watchdog.deadline(1000))
  end)
end)

describe("ntf.core.worker.watchdog.poll_interval", function()
  it("reads the parent five times a second", function()
    assert.equal(200, watchdog.poll_interval())
  end)
end)

--- @param started integer a vim.uv.hrtime reading
--- @return number ms since that reading
local function ms_since(started)
  local ns_per_ms = 1000000
  return (vim.uv.hrtime() - started) / ns_per_ms
end

describe("ntf.core.worker.watchdog.wait", function()
  it("returns to a process whose parent is no longer the one it was born under", function()
    local a_parent_this_process_never_had = 0

    local reason = watchdog.wait(a_parent_this_process_never_had, nil, watchdog.poll_interval())

    assert.equal("orphaned", reason)
  end)

  it("returns before its first sleep to a process whose deadline is already spent", function()
    local a_sleep_no_test_here_waits_out = 10000
    local spent = 0
    local started = vim.uv.hrtime()

    local reason = watchdog.wait(vim.uv.os_getppid(), spent, a_sleep_no_test_here_waits_out)

    assert.equal("deadline", reason)
    assert.is_true(ms_since(started) < a_sleep_no_test_here_waits_out)
  end)

  it("sleeps a whole poll out for a deadline with any time left on it", function()
    local interval_ms = 100
    local shorter_than_one_poll = 1
    local started = vim.uv.hrtime()

    local reason = watchdog.wait(vim.uv.os_getppid(), shorter_than_one_poll, interval_ms)

    assert.equal("deadline", reason)
    assert.is_true(ms_since(started) >= interval_ms)
  end)
end)

describe("ntf.core.worker.watchdog.start", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("kills a process spinning in lua, which no timer of its own could reach", function()
    local script = helper.test_data:create_file(
      "spinner.lua",
      ([[
vim.opt.runtimepath:prepend(%q)
require("ntf.core.worker.watchdog").start(500)
while true do end
]]):format(helper.root)
    )

    local exited = false
    local proc = vim.system({
      vim.v.progpath,
      "--clean",
      "--headless",
      "-c",
      ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(script),
    }, { text = true }, function()
      exited = true
    end)

    -- WHY: what the kill leaves behind is the platform's to choose -- unix
    -- reports the signal on a zero exit code, windows an exit code of 1 and no
    -- signal -- so the claim is the one both agree on: the spin ended, which
    -- nothing but the watchdog could have ended.
    -- NOT: waiting on the SystemObj with a timeout and reading its result, since
    -- that timeout kills with the very SIGKILL the watchdog sends, so a watchdog
    -- that never fired would report exactly what one that did reports.
    local stopped = vim.wait(10000, function()
      return exited
    end, 20)
    if not stopped then
      proc:kill("sigkill")
    end

    assert.equal(true, stopped)
  end)
end)
