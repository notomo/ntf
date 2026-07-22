local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local report = require("ntf.core.mutation.report")

-- WHY: summary() expands the given cwd with fnamemodify(":p"), which on Windows
-- prefixes a drive letter, so the records would no longer sit under the root.
-- NOT: a made-up absolute directory such as "/root".
local root = vim.fs.normalize(vim.fn.getcwd())

--- @param relative_path string
local function abs(relative_path)
  return vim.fs.joinpath(root, relative_path)
end

--- @param path string
--- @param row integer
--- @param status string
local function record(path, row, status)
  return {
    mutant = {
      path = path,
      operator = "swap-relational",
      row = row,
      col = 0,
      end_row = row,
      end_col = 1,
      start_byte = 0,
      end_byte = 1,
      original = "<",
      replacement = "<=",
    },
    status = status,
  }
end

describe("ntf.core.mutation.report.summary", function()
  it("scores the detected mutants and lists the undetected ones", function()
    local summary = {
      records = {
        record(abs("lua/a.lua"), 1, "killed"),
        record(abs("lua/a.lua"), 2, "timeout"),
        record(abs("lua/a.lua"), 3, "survived"),
        record(abs("lua/b.lua"), 4, "no_coverage"),
      },
      counts = { killed = 1, timeout = 1, survived = 1, no_coverage = 1, not_applied = 0, equivalent = 0 },
      score = 50,
    }

    local text = report.summary(summary, root, { color = false })

    assert.match("Mutation: 50%.0%% %(2/4 mutants detected%)", text)
    assert.match("1 killed  1 timeout  1 survived  1 no coverage\n", text)
    assert.match("SURVIVED lua/a%.lua:3 swap%-relational: < %-> <=", text)
    assert.match("NO COVERAGE lua/b%.lua:4", text)
    local detected_mutant = "lua/a%.lua:1"
    assert.no.match(detected_mutant, text)
    local status_nothing_landed_in = "not applied"
    assert.no.match(status_nothing_landed_in, text)
  end)

  it("shows a path relative to the working directory, leaving a path outside it whole", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "survived"), record("/other/b.lua", 2, "survived") },
      counts = { killed = 0, timeout = 0, survived = 2, no_coverage = 0, not_applied = 0, equivalent = 0 },
      score = 0,
    }

    local text = report.summary(summary, root .. "/", { color = false })

    assert.match("SURVIVED lua/a%.lua:1", text)
    assert.match("SURVIVED /other/b%.lua:2", text)
  end)

  it("counts the equivalents apart and lists the lost baseline entries", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed"), record(abs("lua/a.lua"), 2, "equivalent") },
      counts = { killed = 1, timeout = 0, survived = 0, no_coverage = 0, not_applied = 0, equivalent = 1 },
      score = 100,
      lost = {
        {
          path = "lua/b.lua",
          col = 3,
          operator = "flip-boolean",
          original = "true",
          replacement = "false",
          line = "  local x = true",
          rationale = "unused",
        },
      },
    }

    local text = report.summary(summary, root, { color = false })

    assert.match("Mutation: 100%.0%% %(1/1 mutants detected%)", text)
    assert.match("1 equivalent", text)
    local settled_equivalent_mutant = "lua/a%.lua:2"
    assert.no.match(settled_equivalent_mutant, text)
    assert.match('LOST BASELINE lua/b%.lua flip%-boolean: true %-> false at "  local x = true"', text)
  end)

  it("reports n/a when there is no mutant to score", function()
    local summary = {
      records = {},
      counts = { killed = 0, timeout = 0, survived = 0, no_coverage = 0, not_applied = 0, equivalent = 0 },
      score = nil,
    }

    assert.match("Mutation: n/a", report.summary(summary, root, { color = false }))
  end)
end)
