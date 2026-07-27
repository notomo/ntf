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
    if record.killers then
      mutants = mutants + 1
      for _, name in ipairs(record.killers) do
        detected[name] = (detected[name] or 0) + 1
      end
      if #record.killers == 1 then
        distinguishing[record.killers[1]] = true
      end
    end
  end

  -- WHY: iterating in sorted-name order makes the result deterministic even for
  -- tests of equal detection count, whose relative order table.sort would
  -- otherwise leave to the nondeterministic pairs() order of the map above.
  -- NOT: `pairs(detected)`, which reorders the equal-count tests run to run.
  local names = vim.tbl_keys(detected)
  table.sort(names)
  local tests = {}
  for _, name in ipairs(names) do
    if not distinguishing[name] then
      table.insert(tests, { name = name, detected = detected[name] })
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
