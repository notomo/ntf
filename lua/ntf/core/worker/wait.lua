local driver = require("ntf.core.worker.driver")

local M = {}

--- @type integer ms a run waits on its workers when it names no budget of its own, past what any run of a suite takes: every worker is killed at its own timeout, so reaching this is a launcher that lost an item rather than a run that was slow
M.budget_ms = 15 * 60 * 1000

--- @class NtfRunState what a run's worker callbacks report back to the wait
--- @field finished integer work items that have reported back
--- @field running table<any, string> what every item a worker was launched for is called, until it reports back
--- @field fatal any? the error a callback raised, which ends the run before its items are done

--- @class NtfRunGiveUp what a run that spent its budget was still waiting on
--- @field budget integer ms the wait was given
--- @field unfinished integer items that never reported back
--- @field total integer items the run waited on
--- @field unit string what one of them is called
--- @field launched string[] what the ones a worker had been launched for are called, in one order however they were dispatched

--- @param gave_up NtfRunGiveUp
--- @return string # what a report or an error says the run came to
function M.message(gave_up)
  local message = ("after %.1fs: %d of %d %s never reported back"):format(
    gave_up.budget * 1e-3,
    gave_up.unfinished,
    gave_up.total,
    gave_up.unit
  )
  if #gave_up.launched == 0 then
    return message
  end
  return message
    .. (", %d of them from a worker it had launched:\n  %s"):format(
      #gave_up.launched,
      table.concat(gave_up.launched, "\n  ")
    )
end

--- @param state NtfRunState the callbacks keep writing to it while the wait runs
--- @param opts { budget: integer?, total: integer, unit: string } ms this wait may take before it gives up (the run budget when left out), items that must report back, and what one of them is called in what the run comes to
--- @return NtfRunGiveUp? # nil for the run every item reported back to
function M.settle(state, opts)
  local budget = opts.budget or M.budget_ms
  vim.wait(budget, function()
    return state.finished >= opts.total or state.fatal ~= nil
  end, 20)
  driver.kill_all()

  if state.fatal then
    error(state.fatal, 0)
  end

  if state.finished >= opts.total then
    return nil
  end

  local launched = vim.tbl_values(state.running)
  table.sort(launched)
  return {
    budget = budget,
    unfinished = opts.total - state.finished,
    total = opts.total,
    unit = opts.unit,
    launched = launched,
  }
end

return M
