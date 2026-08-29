local wait = require("ntf.core.worker.wait")

local M = {}

--- @type integer ms the shortest a trial gets, however fast the test was in the baseline run
local floor_ms = 3000

--- @type integer how many baselines of the test a trial gets before the headroom
local baseline_factor = 2

--- @type integer ms a trial gets beyond the baselines it is given
local headroom_ms = 2000

--- @type integer ms of the run's budget each mutant earns beyond the floor
local per_mutant_ms = 10 * 1000

--- @param baseline_ms number how long the test took in the baseline run
--- @param timeout integer ms the trial may not exceed: the test's own timeout when it declared one, the run's per-test timeout otherwise (0 disables)
--- @return integer ms after which a trial of that test is killed
function M.trial(baseline_ms, timeout)
  local trial_ms = math.max(floor_ms, baseline_factor * baseline_ms + headroom_ms)
  if timeout > 0 then
    trial_ms = math.min(trial_ms, timeout)
  end
  return math.floor(trial_ms)
end

--- @param total integer mutants the run waits on
--- @return integer ms the whole run may take before it gives up
function M.run(total)
  return wait.budget(total, per_mutant_ms)
end

return M
