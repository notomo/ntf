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

  --- @type integer how long a worker waits between two beats, short enough that several land inside one poll of the parent
  local beat_ms = 50

  --- @type integer beats a worker writes before it stops on its own, bounding a worker no watchdog ever kills
  local beats = 600

  --- @param path string the file a worker beats into
  --- @return integer # bytes it has beaten so far, which only grows
  local function beaten(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.size or 0
  end

  --- @param path string the file a worker beats into
  --- @param deadline_ms integer how long to give the watchdog
  --- @return boolean # whether the beats stopped
  local function beats_stopped(path, deadline_ms)
    local quiet_ms = watchdog.poll_interval() * 3
    local waited = 0
    while waited < deadline_ms do
      local seen = beaten(path)
      vim.uv.sleep(quiet_ms)
      waited = waited + quiet_ms
      if beaten(path) == seen then
        return true
      end
    end
    return false
  end

  --- @param script string path to a lua file
  --- @return table # a vim.SystemObj running it in a headless neovim
  local function nvim(script)
    return vim.system({
      vim.v.progpath,
      "--clean",
      "--headless",
      "-c",
      ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(script),
    }, { text = true })
  end

  it("kills a worker whose run died, leaving it beating into a directory nothing reads", function()
    local heartbeat = helper.test_data:path("heartbeat")
    local worker = helper.test_data:create_file(
      "worker.lua",
      ([[
vim.opt.runtimepath:prepend(%q)
require("ntf.core.worker.watchdog").start(nil)
for _ = 1, %d do
  vim.fn.writefile({ "beat" }, %q, "a")
  vim.uv.sleep(%d)
end
]]):format(helper.root, beats, heartbeat, beat_ms)
    )
    local run = helper.test_data:create_file(
      "run.lua",
      ([[
local worker = vim.system({
  vim.v.progpath,
  "--clean",
  "--headless",
  "-c",
  ("lua vim.cmd.luafile({ args = { %%q }, magic = { file = false } })"):format(%q),
})
local _ = worker
vim.wait(%d, function()
  return false
end)
]]):format(worker, beats * beat_ms)
    )

    local proc = nvim(run)
    local one_beat = #"beat\n"
    local started_beating = vim.wait(30000, function()
      return beaten(heartbeat) >= 2 * one_beat
    end, 20)
    assert.is_true(started_beating)

    proc:kill("sigkill")

    -- WHY: what ends a worker whose run died is the platform's to choose -- unix
    -- reparents it and leaves the watchdog to read the parent it landed on, while
    -- windows ends every process the run spawned along with it -- so the claim is
    -- the one both agree on: the beats stopped, which under unix nothing but the
    -- watchdog could have stopped.
    -- NOT: asserting under windows that the beats go on, which the pid it reports
    -- for a dead parent would suggest and its own kill of the tree denies.
    assert.is_true(beats_stopped(heartbeat, 10000))
  end)

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
