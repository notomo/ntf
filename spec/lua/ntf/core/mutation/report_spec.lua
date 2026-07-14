local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local report = require("ntf.core.mutation.report")

-- A real directory rather than a made-up "/root", because summary() expands
-- cwd with fnamemodify(":p"), which on Windows prefixes a drive letter onto
-- "/root" and the records no longer sit under it.
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
      counts = { killed = 1, timeout = 1, survived = 1, no_coverage = 1, not_applied = 0 },
      score = 50,
    }

    local text = report.summary(summary, root, { color = false })

    assert.match("Mutation: 50%.0%% %(2/4 mutants detected%)", text)
    assert.match("1 killed  1 timeout  1 survived  1 no coverage\n", text)
    assert.match("SURVIVED lua/a%.lua:3 swap%-relational: < %-> <=", text)
    assert.match("NO COVERAGE lua/b%.lua:4", text)
    -- A detected mutant says nothing beyond the score, so it is not listed.
    assert.no.match("lua/a%.lua:1", text)
    -- A status nothing landed in is left out of the counts line.
    assert.no.match("not applied", text)
  end)

  it("shows a path relative to the working directory, however that was spelled", function()
    local summary = {
      records = { record(abs("lua/a.lua"), 1, "survived"), record("/other/b.lua", 2, "survived") },
      counts = { killed = 0, timeout = 0, survived = 2, no_coverage = 0, not_applied = 0 },
      score = 0,
    }

    local text = report.summary(summary, root .. "/", { color = false })

    assert.match("SURVIVED lua/a%.lua:1", text)
    -- A file outside the working directory has no relative form; it stays whole.
    assert.match("SURVIVED /other/b%.lua:2", text)
  end)

  it("reports n/a when there is no mutant to score", function()
    local summary = {
      records = {},
      counts = { killed = 0, timeout = 0, survived = 0, no_coverage = 0, not_applied = 0 },
      score = nil,
    }

    assert.match("Mutation: n/a", report.summary(summary, root, { color = false }))
  end)
end)
