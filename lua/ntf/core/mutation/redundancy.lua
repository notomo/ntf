local M = {}

--- @class NtfRedundantTest
--- @field name string full name of the test
--- @field detected integer mutants it detected, every one of which another test detected too

--- @class NtfRedundancy
--- @field tests NtfRedundantTest[] most-detecting first; none of them detects anything the others miss
--- @field mutants integer mutants whose whole killer set is known, which is all the verdict rests on

--- @param records NtfMutationRecord[]
--- @return NtfRedundancy
function M.analyze(records)
  local detected = {} --- @type table<string, integer>
  local distinguishing = {} --- @type table<string, true>
  local mutants = 0

  for _, record in ipairs(records) do
    -- WHY: a record without a complete killer set stopped at its first kill, so
    -- counting it would make that one test look like the only one that can
    -- detect the mutant and wrongly spare it from the list.
    -- NOT: falling back to `killed_by` for the records the cap left out.
    if record.killers then
      mutants = mutants + 1
      for _, name in ipairs(record.killers) do
        detected[name] = (detected[name] or 0) + 1
      end
      -- WHY: being some mutant's only killer is what makes a test irreplaceable,
      -- so a test that is never one has every kill of its own covered elsewhere.
      -- NOT: comparing kill sets pairwise, which answers the narrower question of
      -- whether one single other test subsumes it.
      if #record.killers == 1 then
        distinguishing[record.killers[1]] = true
      end
    end
  end

  local tests = {}
  for name, count in pairs(detected) do
    if not distinguishing[name] then
      table.insert(tests, { name = name, detected = count })
    end
  end
  table.sort(tests, function(a, b)
    if a.detected ~= b.detected then
      return a.detected > b.detected
    end
    return a.name < b.name
  end)

  return { tests = tests, mutants = mutants }
end

return M
