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
      counts = {
        killed = 1,
        timeout = 1,
        survived = 1,
        no_coverage = 1,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
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
      counts = {
        killed = 0,
        timeout = 0,
        survived = 2,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = 0,
    }

    local text = report.summary(summary, root .. "/", { color = false })

    assert.match("SURVIVED lua/a%.lua:1", text)
    assert.match("SURVIVED /other/b%.lua:2", text)
  end)

  it("counts the equivalents apart and lists the lost baseline entries", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed"), record(abs("lua/a.lua"), 2, "equivalent") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 1,
        baseline_killable = 0,
      },
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

  it("lists the exclude entries that cover no measurable file", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {},
      unpinned = {},
      unused_excludes = { { path = "lua/gone", rationale = "unused" } },
    }

    local text = report.summary(summary, root, { color = false })

    assert.match("UNUSED EXCLUDE lua/gone", text)
  end)

  it("lists the baseline entries whose invariant_spec no test pins", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {},
      unpinned = {
        {
          path = "lua/b.lua",
          col = 3,
          operator = "flip-boolean",
          original = "true",
          replacement = "false",
          line = "  local x = true",
          rationale = "unused",
          invariant_spec = "mod keeps a and b apart",
        },
      },
    }

    local text = report.summary(summary, root, { color = false })

    assert.match(
      'UNPINNED BASELINE lua/b%.lua flip%-boolean: true %-> false wants a passing "mod keeps a and b apart"',
      text
    )
  end)

  it("lists a baseline-killable mutant apart from the score", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed"), record(abs("lua/a.lua"), 2, "baseline_killable") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 1,
      },
      score = 100,
    }

    local text = report.summary(summary, root, { color = false })

    assert.match("Mutation: 100%.0%% %(1/1 mutants detected%)", text)
    assert.match("1 baseline killable", text)
    assert.match("BASELINE KILLABLE lua/a%.lua:2 swap%-relational: < %-> <=", text)
  end)

  it("lists the redundant tests once the killer sets are known", function()
    local killed = record(abs("lua/a.lua"), 1, "killed")
    killed.killers = { "spec a", "spec b" }
    local also_killed = record(abs("lua/a.lua"), 2, "killed")
    also_killed.killers = { "spec b" }
    local summary = {
      records = { killed, also_killed },
      counts = {
        killed = 2,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = 100,
    }

    local text = report.summary(summary, root, { color = false })

    assert.match("Matrix: 2 mutants fully tried", text)
    assert.match("REDUNDANT spec a %(detected 1, none of them alone%)", text)
    local only_killer_of_the_second_mutant = "REDUNDANT spec b"
    assert.no.match(only_killer_of_the_second_mutant, text)
  end)

  it("counts a lone fully tried mutant into the matrix", function()
    local killed = record(abs("lua/a.lua"), 1, "killed")
    killed.killers = { "spec a" }
    local summary = {
      records = { killed },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = 100,
    }

    assert.match("Matrix: 1 mutants fully tried", report.summary(summary, root, { color = false }))
  end)

  it("says nothing about the matrix when no killer set was recorded", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = 100,
    }

    assert.no.match("Matrix:", report.summary(summary, root, { color = false }))
  end)

  it("reports n/a when there is no mutant to score", function()
    local summary = {
      records = {},
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        baseline_killable = 0,
      },
      score = nil,
    }

    assert.match("Mutation: n/a", report.summary(summary, root, { color = false }))
  end)
end)
