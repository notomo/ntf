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
--- @param mutant table? what the mutant differs in from a one-column swap-relational
local function record(path, row, status, mutant)
  return {
    mutant = vim.tbl_extend("force", {
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
    }, mutant or {}),
    status = status,
  }
end

describe("ntf.core.mutation.report.summary", function()
  it("names the batches a kill was taken back from, and counts them", function()
    local mutant = record(abs("lua/a.lua"), 7, "killed").mutant
    local summary = {
      records = {},
      restarted = {
        { mutant = mutant, killed_by = "a leaky test" },
        { mutant = mutant, killed_by = "another leaky test" },
      },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 1.0 })

    assert.match("  2 batches restarted after a kill did not reproduce alone\n", text)
    assert.match(
      'FLAKY BATCH lua/a%.lua:7:1:swap%-relational < %-> <= killed by "a leaky test" only where a process was shared',
      text
    )
    assert.match('killed by "another leaky test"', text)
  end)

  it("counts one restarted batch in the singular", function()
    local summary = {
      records = {},
      restarted = { { mutant = record(abs("lua/a.lua"), 7, "killed").mutant, killed_by = "a leaky test" } },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 1.0 })

    assert.match("  1 batch restarted after a kill did not reproduce alone\n", text)
  end)

  it("says nothing about batches where every kill reproduced alone", function()
    local summary = {
      records = {},
      restarted = {},
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 1.0 })

    assert.no.match("restarted", text)
    assert.no.match("FLAKY BATCH", text)
  end)

  it("scores the detected mutants and lists every one a test did not plainly fail on", function()
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 50,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 52.0 })

    assert.match("Mutation: 50%.0%% %(2/4 mutants detected%), 52%.0s elapsed\n", text)
    assert.match("1 killed  1 timeout  1 survived  1 no coverage\n", text)
    assert.match("TIMEOUT lua/a%.lua:2:1:swap%-relational < %-> <=", text)
    assert.match("SURVIVED lua/a%.lua:3:1:swap%-relational < %-> <=", text)
    assert.match("NO COVERAGE lua/b%.lua:4", text)
    local killed_mutant = "lua/a%.lua:1"
    assert.no.match(killed_mutant, text)
    local status_nothing_landed_in = "not applied"
    assert.no.match(status_nothing_landed_in, text)
  end)

  it("lists a mutant that never landed apart from the undetected ones", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed"), record(abs("lua/a.lua"), 2, "not_applied") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 1,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("Mutation: 100%.0%% %(1/1 mutants detected%)", text)
    assert.match("1 killed  1 not applied\n", text)
    assert.match("NOT APPLIED lua/a%.lua:2:1:swap%-relational < %-> <=", text)
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 0,
    }

    local text = report.summary(summary, root .. "/", { color = false, elapsed = 0 })

    assert.match("SURVIVED lua/a%.lua:1", text)
    assert.match("SURVIVED /other/b%.lua:2", text)
  end)

  it("tells two mutants of one row apart by their columns", function()
    local summary = {
      records = {
        record(abs("lua/a.lua"), 1, "survived", { col = 12 }),
        record(abs("lua/a.lua"), 1, "survived", { col = 4 }),
      },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 2,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 0,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match(vim.pesc("SURVIVED lua/a.lua:1:13:swap-relational < -> <="), text)
    assert.match(vim.pesc("SURVIVED lua/a.lua:1:5:swap-relational < -> <="), text)
  end)

  it("lists a mutant whose source spans lines on one line, cut to a readable width", function()
    local sixty_characters = "f(" .. ("a"):rep(57) .. ")"
    local summary = {
      records = {
        record(abs("lua/a.lua"), 1, "survived", {
          operator = "drop-call",
          original = "f(\n  a\n)",
          replacement = "do end",
        }),
        record(abs("lua/a.lua"), 2, "survived", {
          operator = "drop-call",
          original = "vim.iter(collected_items):each(function(item)\n  print(item.name)\nend)",
          replacement = "do end",
        }),
        record(abs("lua/a.lua"), 3, "survived", {
          operator = "drop-call",
          original = sixty_characters,
          replacement = "do end",
        }),
      },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 3,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 0,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match(vim.pesc("SURVIVED lua/a.lua:1:1:drop-call f( a ) -> do end\n"), text)
    assert.match(
      vim.pesc(
        "SURVIVED lua/a.lua:2:1:drop-call vim.iter(collected_items):each(function(item) print(item.na… -> do end\n"
      ),
      text
    )
    local text_the_width_leaves_whole =
      vim.pesc(("SURVIVED lua/a.lua:3:1:drop-call %s -> do end\n"):format(sixty_characters))
    assert.match(text_the_width_leaves_whole, text)
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {
        {
          path = "lua/b.lua",
          col = 3,
          operator = "swap-boolean",
          original = "true",
          replacement = "false",
          line = "  local x = true",
          rationale = "unused",
        },
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("Mutation: 100%.0%% %(1/1 mutants detected%)", text)
    assert.match("1 equivalent", text)
    local settled_equivalent_mutant = "lua/a%.lua:2"
    assert.no.match(settled_equivalent_mutant, text)
    assert.match('LOST BASELINE lua/b%.lua swap%-boolean: true %-> false at "  local x = true"', text)
  end)

  it("lists a baseline position whose content named more than one mutant", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {},
      ambiguous = {
        {
          entry = {
            path = "lua/b.lua",
            col = 3,
            operator = "swap-boolean",
            original = "true",
            replacement = "false",
            line = "  local x = true",
            rationale = "unused",
          },
          rows = { 26, 29 },
        },
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match(
      "AMBIGUOUS BASELINE lua/b%.lua swap%-boolean: true %-> false names rows 26, 29; give each entry its row",
      text
    )
  end)

  it("counts the mutants an exclude entry's operator left out", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed"), record(abs("lua/b.lua"), 2, "excluded") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 1,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("1 killed  1 excluded\n", text)
    local settled_excluded_mutant = "lua/b%.lua:2"
    assert.no.match(settled_excluded_mutant, text)
  end)

  it("counts the mutants of an operator the config did not adopt", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 7,
        baseline_killable = 0,
      },
      score = 100,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("1 killed  7 unadopted\n", text)
    local nagging_line = "UNADOPTED"
    assert.no.match(nagging_line, text)
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {},
      unpinned = {},
      unused_excludes = { { path = "lua/gone", rationale = "unused" } },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("UNUSED EXCLUDE lua/gone", text)
  end)

  it("lists the exclude_spec entries that cover no discovered spec file", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {},
      unpinned = {},
      unused_excludes = {},
      unused_spec_excludes = { { path = "spec/gone_spec.lua", rationale = "unused" } },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("UNUSED EXCLUDE SPEC spec/gone_spec%.lua", text)
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      lost = {},
      unpinned = {
        {
          path = "lua/b.lua",
          col = 3,
          operator = "swap-boolean",
          original = "true",
          replacement = "false",
          line = "  local x = true",
          rationale = "unused",
          invariant_spec = "mod keeps a and b apart",
        },
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match(
      'UNPINNED BASELINE lua/b%.lua swap%-boolean: true %-> false wants a passing "mod keeps a and b apart"',
      text
    )
  end)

  it("lists the baseline entries no test reaches, which carry no uncovered to say so", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      uncovered = {
        {
          path = "lua/b.lua",
          col = 3,
          operator = "swap-boolean",
          original = "true",
          replacement = "false",
          line = "  local x = true",
          rationale = "unused",
        },
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("UNCOVERED BASELINE lua/b%.lua swap%-boolean: true %-> false is reached by no test", text)
  end)

  it("lists the uncovered baseline entries a test does reach", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "killed") },
      counts = {
        killed = 1,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = 100,
      covered = {
        {
          path = "lua/b.lua",
          col = 3,
          operator = "swap-boolean",
          original = "true",
          replacement = "false",
          line = "  local x = true",
          rationale = "unused",
          uncovered = true,
        },
      },
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("COVERED BASELINE lua/b%.lua swap%-boolean: true %-> false is reached by a test now", text)
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 1,
      },
      score = 100,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("Mutation: 100%.0%% %(1/1 mutants detected%)", text)
    assert.match("1 baseline killable", text)
    assert.match("BASELINE KILLABLE lua/a%.lua:2:1:swap%-relational < %-> <=", text)
  end)

  it("names the test that killed a baseline entry, since every covering trial ran", function()
    local killable = record(abs("lua/a.lua"), 2, "baseline_killable")
    killable.killed_by = "ntf.core.mod keeps a and b apart"
    local summary = {
      records = { killable },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 1,
      },
      verified = 1,
      baseline_uncovered = 0,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match(
      'BASELINE KILLABLE lua/a%.lua:2:1:swap%-relational < %-> <= killed by "ntf%.core%.mod keeps a and b apart"',
      text
    )
  end)

  it("counts the baseline entries re-run in place of a score when verifying the baseline", function()
    local summary = {
      records = {
        record(abs("lua/a.lua"), 1, "equivalent"),
        record(abs("lua/a.lua"), 2, "equivalent"),
        record(abs("lua/a.lua"), 3, "baseline_killable"),
      },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 2,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 1,
      },
      verified = 2,
      baseline_uncovered = 0,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 12.34 })

    assert.match("Baseline: 2/3 entries re%-run, 12%.3s elapsed\n", text)
    assert.match("BASELINE KILLABLE lua/a%.lua:3:1:swap%-relational < %-> <=", text)
    local score_line = "Mutation:"
    assert.no.match(score_line, text)
  end)

  it("counts the entries it stood behind apart from the ones it re-ran", function()
    local summary = {
      records = {
        record(abs("lua/a.lua"), 1, "equivalent"),
        record(abs("lua/a.lua"), 2, "equivalent"),
      },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 0,
        equivalent = 2,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      verified = 1,
      baseline_uncovered = 1,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.match("Baseline: 1/2 entries re%-run, 1 uncovered,", text)
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
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = nil,
    }

    assert.equal(
      "Mutation: n/a (no mutants), 0ms elapsed\n",
      report.summary(summary, root, { color = false, elapsed = 0 })
    )
  end)

  it("counts the mutants that left the score even though none of them was scored", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "not_applied") },
      counts = {
        killed = 0,
        timeout = 0,
        survived = 0,
        no_coverage = 0,
        not_applied = 1,
        equivalent = 0,
        excluded = 0,
        unadopted = 0,
        baseline_killable = 0,
      },
      score = nil,
    }

    local text = report.summary(summary, root, { color = false, elapsed = 0 })

    assert.equal(table.concat({
      "Mutation: n/a (no mutant scored), 0ms elapsed",
      "  1 not applied",
      "NOT APPLIED lua/a.lua:1:1:swap-relational < -> <=",
    }, "\n") .. "\n", text)
  end)
end)
