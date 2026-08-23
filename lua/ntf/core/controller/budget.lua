local wait = require("ntf.core.worker.wait")

local M = {}

--- @type integer ms of the run's budget each test earns beyond the floor
local per_test_ms = 10 * 1000

--- @param total integer tests the run waits on
--- @return integer ms the whole run may take before it gives up
function M.run(total)
  return wait.budget(total, per_test_ms)
end

return M
