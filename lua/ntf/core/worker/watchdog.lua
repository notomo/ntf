local M = {}

--- @param timeout integer the run's per-worker timeout in ms
--- @return integer ms after which the worker kills itself, late enough that the run's own kill wins whenever the run is still there to make it
function M.deadline(timeout)
  --- @type integer how long a worker outlives the timeout the run would kill it at
  local parent_kill_grace_ms = 30000
  return timeout + parent_kill_grace_ms
end

-- WHY: the timer that kills a worker lives in the process that launched it, so a
-- run that dies leaves its workers with no deadline at all, and one spinning in
-- pure Lua reaches neither its own event loop nor a signal handler. A thread of
-- its own runs while the main Lua state spins, and SIGKILL is uncatchable.
-- NOT: a `debug.sethook` count hook, which does fire while the state spins but
-- takes the single hook slot `ntf.core.coverage.collector` installs its line hook
-- in, so a measured run would report no coverage.
--- @param deadline_ms integer kill this process after this long
function M.start(deadline_ms)
  local default_thread_options = {}
  vim.uv.new_thread(default_thread_options, function(pid, ms)
    vim.uv.sleep(ms)
    vim.uv.kill(pid, "sigkill")
  end, vim.uv.os_getpid(), deadline_ms)
end

return M
