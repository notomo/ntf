local driver = require("ntf.core.worker.driver")

local M = {}

--- @type integer ms a run waits on its workers when it names no budget of its own, past what any run of a suite takes: every worker is killed at its own timeout, so reaching this is a launcher that lost an item rather than a run that was slow
M.budget_ms = 15 * 60 * 1000

--- @class NtfRunState what a run's worker callbacks report back to the wait
--- @field finished integer work items that have reported back
--- @field running table<any, string> what every item a worker was launched for is called, until it reports back
--- @field fatal any? the error a callback raised, which ends the run before its items are done

--- @param state NtfRunState
--- @param budget integer ms the wait was given
--- @param opts { budget: integer?, total: integer, unit: string }
--- @return string # what the run raises, naming the items it was still waiting on
local function gave_up(state, budget, opts)
  local message = ("the run gave up after %.1fs: %d of %d %s never reported back"):format(
    budget * 1e-3,
    opts.total - state.finished,
    opts.total,
    opts.unit
  )

  local launched = vim.tbl_values(state.running)
  if #launched == 0 then
    return message
  end
  table.sort(launched)
  return message
    .. (", %d of them from a worker it had launched:\n  %s"):format(#launched, table.concat(launched, "\n  "))
end

--- @param state NtfRunState the callbacks keep writing to it while the wait runs
--- @param opts { budget: integer?, total: integer, unit: string } ms this wait may take before it gives up (the run budget when left out), items that must report back, and what one of them is called in the message a run that ran out raises
function M.settle(state, opts)
  local budget = opts.budget or M.budget_ms
  vim.wait(budget, function()
    return state.finished >= opts.total or state.fatal ~= nil
  end, 20)
  driver.kill_all()

  if state.fatal then
    error(state.fatal, 0)
  end

  if state.finished < opts.total then
    error(gave_up(state, budget, opts), 0)
  end
end

return M
