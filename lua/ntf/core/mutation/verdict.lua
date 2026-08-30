local tree = require("ntf.core.tree")

local M = {}

--- @class NtfMutantOutcome
--- @field status "killed"|"timeout"|"survived"|"not_applied"
--- @field killed_by string? full name of the test that detected the mutant

--- @class NtfMutantProgress what the trials run so far have shown
--- @field applied boolean whether any trial actually loaded the mutated source

--- @return NtfMutantProgress
function M.new_progress()
  return { applied = false }
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
--- @return NtfMutantOutcome? # the mutant's verdict, nil to run the next trial
--- @return NtfMutantProgress # what the next trial starts from
function M.step(outcome, progress)
  if outcome.timed_out then
    return { status = "timeout" }, progress
  end

  if outcome.mutation_applied == false then
    return nil, progress
  end

  local killed_by = detected_by(outcome.results)
  if killed_by then
    return { status = "killed", killed_by = killed_by }, { applied = true }
  end

  return nil, { applied = true }
end

--- @param progress NtfMutantProgress
--- @return NtfMutantOutcome # the verdict once no trial is left to run
function M.exhausted(progress)
  if not progress.applied then
    return { status = "not_applied" }
  end
  return { status = "survived" }
end

return M
