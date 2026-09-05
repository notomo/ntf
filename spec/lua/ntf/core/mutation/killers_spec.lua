local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local killers = require("ntf.core.mutation.killers")

--- @param row integer
--- @param killed_by string?
--- @param over table? what the record differs in from a one-column swap-relational
--- @return table # one NtfMutationResultRecord
local function record(row, killed_by, over)
  return vim.tbl_extend("force", {
    row = row,
    col = 9,
    end_row = row,
    end_col = 10,
    operator = "swap-relational",
    original = "<",
    replacement = "<=",
    status = killed_by and "killed" or "survived",
    killed_by = killed_by,
  }, over or {})
end

--- @param row integer
--- @param over table? what the mutant differs in from a one-column swap-relational
--- @return table # one NtfMutant
local function mutant(row, over)
  return vim.tbl_extend("force", { path = "/p/lua/mod.lua" }, record(row, nil, over))
end

describe("ntf.core.mutation.killers.previous_killer", function()
  it("names the test that killed that very mutant", function()
    local killer = killers.previous_killer({ files = { ["/p/lua/mod.lua"] = { record(3, "killed it") } } })

    assert.equal("killed it", killer(mutant(3)))
  end)

  it("names nobody for a mutant of another row, column, operator or replacement", function()
    local killer = killers.previous_killer({ files = { ["/p/lua/mod.lua"] = { record(3, "killed it") } } })

    assert.is_nil(killer(mutant(4)))
    assert.is_nil(killer(mutant(3, { col = 10 })))
    assert.is_nil(killer(mutant(3, { operator = "swap-boolean" })))
    assert.is_nil(killer(mutant(3, { replacement = ">=" })))
  end)

  it("names nobody for the same mutant of another file", function()
    local killer = killers.previous_killer({ files = { ["/p/lua/other.lua"] = { record(3, "killed it") } } })

    assert.is_nil(killer(mutant(3)))
  end)

  it("names nobody for a mutant the run before did not kill", function()
    local killer = killers.previous_killer({ files = { ["/p/lua/mod.lua"] = { record(3, nil) } } })

    assert.is_nil(killer(mutant(3)))
  end)

  it("names nobody where no run has filed results yet", function()
    local killer = killers.previous_killer(nil)

    assert.is_nil(killer(mutant(3)))
  end)
end)
