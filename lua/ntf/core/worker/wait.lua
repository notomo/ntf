local driver = require("ntf.core.worker.driver")

local M = {}

--- @class NtfRunState what a run's worker callbacks report back to the wait
--- @field finished integer work items that have reported back
--- @field running table<any, string> what every item a worker was launched for is called, until it reports back
--- @field fatal any? the error a callback raised, which ends the run before its items are done

--- @param state NtfRunState
--- @param opts { budget: integer, total: integer, unit: string }
--- @return string # what the run raises, naming the items it was still waiting on
local function gave_up(state, opts)
  local message = ("the run gave up after %.1fs: %d of %d %s never reported back"):format(
    opts.budget * 1e-3,
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
--- @param opts { budget: integer, total: integer, unit: string } ms the whole run may take (0 waits for as long as the run takes), items that must report back, and what one of them is called in the message a run that ran out raises
function M.settle(state, opts)
  -- WHY: vim.wait rejects a negative timeout, so an endless wait is spelled as
  -- an infinite one.
  -- NOT: -1, which the APIs around it take for a wait without a deadline.
  local budget = opts.budget > 0 and opts.budget or math.huge
  vim.wait(budget, function()
    return state.finished >= opts.total or state.fatal ~= nil
  end, 20)
  driver.kill_all()

  if state.fatal then
    error(state.fatal, 0)
  end

  if state.finished < opts.total then
    error(gave_up(state, opts), 0)
  end
end

return M
