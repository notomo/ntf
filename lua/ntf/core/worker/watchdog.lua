local M = {}

--- @param timeout integer the run's per-worker timeout in ms
--- @return integer ms after which the worker kills itself, late enough that the run's own kill wins whenever the run is still there to make it
function M.deadline(timeout)
  --- @type integer how long a worker outlives the timeout the run would kill it at
  local parent_kill_grace_ms = 30000
  return timeout + parent_kill_grace_ms
end

--- @return integer ms between two reads of the parent
function M.poll_interval()
  return 200
end

-- WHY: a process whose parent is gone is reparented to the nearest subreaper,
-- which is init only when no ancestor claimed that role, so the pid it lands on
-- is not knowable from here -- only that it is no longer the one it was born
-- under.
-- NOT: comparing against 1, which never comes true for a run under a subreaper
-- of its own: a service manager, a container's init, a shell that claimed its
-- descendants.
--- @param original_ppid integer the parent the process was born under
--- @param deadline_ms integer? give up on the parent after this long, nil to wait on it alone
--- @param interval_ms integer how long to sleep between two reads of the parent
--- @return "orphaned"|"deadline" # what ended the wait
function M.wait(original_ppid, deadline_ms, interval_ms)
  local deadline = deadline_ms or math.huge
  local waited = 0
  while vim.uv.os_getppid() == original_ppid do
    if waited >= deadline then
      return "deadline"
    end
    vim.uv.sleep(interval_ms)
    waited = waited + interval_ms
  end
  return "orphaned"
end

-- WHY: the timer that kills a worker lives in the process that launched it, so a
-- run that dies leaves its workers with no deadline at all, and one spinning in
-- pure Lua reaches neither its own event loop nor a signal handler. A thread of
-- its own runs while the main Lua state spins, and SIGKILL is uncatchable.
-- NOT: a `debug.sethook` count hook, which does fire while the state spins but
-- takes the single hook slot `ntf.core.coverage.collector` installs its line hook
-- in, so a measured run would report no coverage.
--- @param deadline_ms integer? kill this process after this long, nil to kill it only once its parent is gone
function M.start(deadline_ms)
  local default_thread_options = {}
  vim.uv.new_thread(default_thread_options, function(pid, original_ppid, ms)
    local watchdog = require("ntf.core.worker.watchdog")
    watchdog.wait(original_ppid, ms, watchdog.poll_interval())
    vim.uv.kill(pid, "sigkill")
  end, vim.uv.os_getpid(), vim.uv.os_getppid(), deadline_ms)
end

return M
