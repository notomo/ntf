local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local list = require("ntf.core.controller.list")

--- @param overrides table?
--- @return table # NtfMutantListEntry
local function mutant_entry(overrides)
  return vim.tbl_deep_extend("force", {
    mutant = {
      path = "/repo/lua/mod.lua",
      row = 3,
      col = 11,
      end_row = 3,
      end_col = 12,
      operator = "swap-relational",
      original = ">",
      replacement = ">=",
    },
    relative_path = "lua/mod.lua",
    covered_count = 0,
    equivalent = false,
  }, overrides or {})
end

describe("ntf.core.controller.list.tests", function()
  it("formats one path:line: full name line per test", function()
    local text = list.tests({
      {
        file = "x",
        node_id = "1",
        names = { "group", "adds" },
        trace = { source = "@" .. vim.fs.joinpath(vim.fn.getcwd(), "spec/x_spec.lua"), line = 12 },
      },
    })

    assert.equal("spec/x_spec.lua:12: group adds\n", text)
  end)

  it("renders no tests as empty text", function()
    assert.equal("", list.tests({}))
  end)
end)

describe("ntf.core.controller.list.mutants", function()
  it("counts the covering tests in the annotation", function()
    local text = list.mutants({ mutant_entry({ covered_count = 4 }) })

    assert.equal("lua/mod.lua:3:11: swap-relational: > -> >= (covered by 4 tests)\n", text)
  end)

  it("uses the singular for a single covering test", function()
    local text = list.mutants({ mutant_entry({ covered_count = 1 }) })

    assert.match("%(covered by 1 test%)\n$", text)
  end)

  it("marks a mutant no test reaches", function()
    local text = list.mutants({ mutant_entry({ covered_count = 0 }) })

    assert.match("%(no coverage%)\n$", text)
  end)

  it("marks a baseline-matched mutant as equivalent, regardless of coverage", function()
    local text = list.mutants({ mutant_entry({ covered_count = 4, equivalent = true }) })

    assert.match("%(equivalent%)\n$", text)
  end)

  it("renders no mutants as empty text", function()
    assert.equal("", list.mutants({}))
  end)
end)

describe("ntf.core.controller.list.load_errors", function()
  it("renders the LOAD ERROR block shape without color", function()
    local text = list.load_errors({
      { file = vim.fs.joinpath(vim.fn.getcwd(), "spec/broken_spec.lua"), message = "boom" },
    })

    assert.equal("LOAD ERROR spec/broken_spec.lua\n    boom\n", text)
  end)

  it("renders no load errors as empty text", function()
    assert.equal("", list.load_errors({}))
  end)
end)
