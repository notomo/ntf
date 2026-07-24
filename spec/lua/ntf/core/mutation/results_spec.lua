local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local results = require("ntf.core.mutation.results")
local helper = require("ntf.test.helper")

--- @param path string
--- @param row integer
--- @param operator string
--- @param status string
--- @param col integer?
local function record(path, row, operator, status, col)
  return {
    mutant = {
      path = path,
      operator = operator,
      row = row,
      col = col or 0,
      end_row = row,
      end_col = (col or 0) + 2,
      start_byte = 0,
      end_byte = 2,
      original = "<",
      replacement = "<=",
    },
    status = status,
  }
end

describe("ntf.core.mutation.results", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("writes the records grouped by file", function()
    local out = helper.test_data:path("ntf-mutation.json")
    local summary = {
      records = { record("/x.lua", 2, "swap-relational", "survived"), record("/x.lua", 1, "flip-boolean", "killed") },
      counts = { killed = 1, timeout = 0, survived = 1, no_coverage = 0, not_applied = 0 },
      score = 50,
    }

    results.write(out, summary)

    local decoded = assert(results.read(out))
    assert.equal(1, decoded.version)
    assert.equal(50, decoded.score)
    assert.equal(1, decoded.counts.survived)
    assert.same({ 1, 2 }, {
      decoded.files["/x.lua"][1].row,
      decoded.files["/x.lua"][2].row,
    })
    assert.equal("survived", decoded.files["/x.lua"][2].status)
  end)

  it("orders two mutants on one line by their column", function()
    local out = helper.test_data:path("ntf-mutation.json")
    local summary = {
      records = {
        record("/x.lua", 1, "swap-relational", "survived", 8),
        record("/x.lua", 1, "swap-relational", "killed", 4),
      },
      counts = { killed = 1, timeout = 0, survived = 1, no_coverage = 0, not_applied = 0 },
      score = 50,
    }

    results.write(out, summary)

    local decoded = assert(results.read(out))
    assert.same({ 4, 8 }, {
      decoded.files["/x.lua"][1].col,
      decoded.files["/x.lua"][2].col,
    })
  end)

  it("writes an empty file map as an object", function()
    local out = helper.test_data:path("ntf-mutation.json")
    local summary = {
      records = {},
      counts = { killed = 0, timeout = 0, survived = 0, no_coverage = 0, not_applied = 0 },
      score = nil,
    }

    results.write(out, summary)

    local decoded = assert(results.read(out))
    assert.same({}, decoded.files)
    assert.is_nil(decoded.score)
  end)

  it("round-trips the killer set of a matrix run", function()
    local out = helper.test_data:path("ntf-mutation.json")
    local killed = record("/x.lua", 1, "flip-boolean", "killed")
    killed.killers = { "spec a", "spec b" }
    local summary = {
      records = { killed, record("/x.lua", 2, "flip-boolean", "killed") },
      counts = { killed = 2, timeout = 0, survived = 0, no_coverage = 0, not_applied = 0 },
      score = 100,
    }

    results.write(out, summary)

    local decoded = assert(results.read(out))
    assert.same({ "spec a", "spec b" }, decoded.files["/x.lua"][1].killers)
    assert.is_nil(decoded.files["/x.lua"][2].killers)
  end)

  it("returns nil for a missing file", function()
    assert.is_nil(results.read(helper.test_data:path("nope.json")))
  end)
end)
