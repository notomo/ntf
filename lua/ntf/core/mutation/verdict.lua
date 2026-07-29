local tree = require("ntf.core.tree")

local M = {}

--- @class NtfMutantOutcome
--- @field status "killed"|"timeout"|"survived"|"not_applied"
--- @field killed_by string? full name of the first test that detected the mutant
--- @field killers string[]? every test that detected the mutant; set only once all its trials ran, so its presence means the set is complete

--- @class NtfMutantProgress what the trials run so far have shown
--- @field killers string[] full names of the tests that detected the mutant, in trial order
--- @field applied boolean whether any trial actually loaded the mutated source

--- @return NtfMutantProgress
function M.new_progress()
  return { killers = {}, applied = false }
end

--- @param results NtfResult[]
--- @return string? # full name of the first test that came back failed or errored
local function detected_by(results)
  for _, result in ipairs(results) do
    if result.status == "failed" or result.status == "error" then
      return tree.full_name(result.names or {})
    end
  end
  return nil
end

--- @param outcome NtfWorkerOutcome one trial's result
--- @param progress NtfMutantProgress what the earlier trials showed
--- @param exhaustive boolean? keep going after a kill, to learn the whole killer set
--- @return NtfMutantOutcome? # the mutant's verdict, nil to run the next trial
--- @return NtfMutantProgress # what the next trial starts from
function M.step(outcome, progress, exhaustive)
  if outcome.timed_out then
    if #progress.killers > 0 then
      return { status = "killed", killed_by = progress.killers[1] }, progress
    end
    return { status = "timeout" }, progress
  end

  local killed_by = detected_by(outcome.results)
  if killed_by then
    local killers = vim.list_extend({}, progress.killers)
    table.insert(killers, killed_by)
    local next_progress = { killers = killers, applied = true }
    if exhaustive then
      return nil, next_progress
    end
    return { status = "killed", killed_by = killers[1] }, next_progress
  end

  if outcome.mutation_applied == false then
    return nil, progress
  end

  return nil, { killers = progress.killers, applied = true }
end

--- @param progress NtfMutantProgress
--- @param exhaustive boolean? keep going after a kill, to learn the whole killer set
--- @return NtfMutantOutcome # the verdict once no trial is left to run
function M.exhausted(progress, exhaustive)
  if #progress.killers > 0 then
    return { status = "killed", killed_by = progress.killers[1], killers = progress.killers }
  end
  if not progress.applied then
    return { status = "not_applied" }
  end
  return { status = "survived", killers = exhaustive and progress.killers or nil }
end

return M
