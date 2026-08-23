local driver = require("ntf.core.worker.driver")

local M = {}

--- @type integer ms the shortest a run gets, however few items it waits on
local floor_ms = 10 * 60 * 1000

--- @param total integer items the run waits on
--- @param per_item_ms integer how much of the budget each item earns beyond the floor
--- @return integer ms the whole run may take before it gives up
function M.budget(total, per_item_ms)
  return math.max(floor_ms, total * per_item_ms)
end

--- @class NtfRunState what a run's worker callbacks report back to the wait
--- @field finished integer work items that have reported back
--- @field fatal any? the error a callback raised, which ends the run before its items are done

--- @param state NtfRunState the callbacks keep writing to it while the wait runs
--- @param opts { budget: integer, total: integer, unit: string } ms the whole run may take, items that must report back, and what one of them is called in the message a run that ran out raises
function M.settle(state, opts)
  vim.wait(opts.budget, function()
    return state.finished >= opts.total or state.fatal ~= nil
  end, 20)
  driver.kill_all()

  if state.fatal then
    error(state.fatal, 0)
  end

  if state.finished < opts.total then
    error(
      ("the run gave up after %.1fs: %d of %d %s never reported back"):format(
        opts.budget * 1e-3,
        opts.total - state.finished,
        opts.total,
        opts.unit
      ),
      0
    )
  end
end

return M
