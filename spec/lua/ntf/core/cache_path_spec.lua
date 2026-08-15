local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local cache_path = require("ntf.core.cache_path")

--- @return string
local function escaped_cwd()
  return table.concat(vim.split(vim.fs.normalize(vim.fn.getcwd()), "[/\\:]"), "%")
end

describe("ntf.core.cache_path", function()
  it("files the schedule cache under the cache directory, named for the working directory", function()
    local path = cache_path.schedule()

    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "schedule"), vim.fs.dirname(path))
    assert.equal(escaped_cwd() .. ".json", vim.fs.basename(path))
  end)

  it("files the mutation results under the cache directory, named for the working directory", function()
    local path = cache_path.mutation_results()

    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "mutation"), vim.fs.dirname(path))
    assert.equal(escaped_cwd() .. ".json", vim.fs.basename(path))
  end)

  it("files the coverage stats under the cache directory, named for the working directory", function()
    local path = cache_path.coverage_stats()

    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "coverage"), vim.fs.dirname(path))
    assert.equal(escaped_cwd() .. ".out", vim.fs.basename(path))
  end)
end)
