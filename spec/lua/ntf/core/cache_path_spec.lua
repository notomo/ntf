local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local cache_path = require("ntf.core.cache_path")
local absolute = require("ntf.core.path").absolute

--- @param dir string
--- @return string
local function escaped(dir)
  return table.concat(vim.split(absolute(dir), "[/\\:]"), "%")
end

--- @return string
local function escaped_cwd()
  return escaped(vim.fn.getcwd())
end

describe("ntf.core.cache_path", function()
  it("files everything under one directory of the cache", function()
    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf"), cache_path.root())
  end)

  it("names the path a cache file was named for, back through the escaping", function()
    local source = vim.fs.joinpath(vim.fn.getcwd(), "lua", "mod.lua")

    assert.equal(absolute(vim.fn.getcwd()), cache_path.named_for(cache_path.schedule()))
    assert.equal(absolute(source), cache_path.named_for(cache_path.instrumented(source)))
  end)

  it("gives a drive letter its colon back, which was escaped like the separator after it", function()
    assert.equal(
      "C:/Users/me/mod.lua",
      cache_path.named_for("/cache/ntf/instrumented/C%%Users%me%mod.lua.instrumented")
    )
  end)

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

  it("files a worker's payload under the cache directory, named for the worker it carries one for", function()
    local nonce = ("a"):rep(32)

    local path = cache_path.payload(nonce)

    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "payload"), vim.fs.dirname(path))
    assert.equal(nonce .. ".json", vim.fs.basename(path))
  end)

  it("files an instrumented copy under the cache directory, named for the source it holds", function()
    local source = vim.fs.joinpath(vim.fn.getcwd(), "lua", "mod.lua")

    local path = cache_path.instrumented(source)

    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "instrumented"), vim.fs.dirname(path))
    assert.equal(escaped(source) .. ".instrumented", vim.fs.basename(path))
  end)

  it("gives an instrumented copy no name a run would take for code under test", function()
    local path = cache_path.instrumented(vim.fs.joinpath(vim.fn.getcwd(), "lua", "mod.lua"))

    assert.no.match("%.lua$", path)
  end)

  it("names the files for the directory it is given, not for the current one", function()
    local dir = vim.fs.dirname(vim.fn.getcwd())

    assert.equal(escaped(dir) .. ".json", vim.fs.basename(cache_path.mutation_results(dir)))
    assert.equal(escaped(dir) .. ".out", vim.fs.basename(cache_path.coverage_stats(dir)))
  end)

  it("names a relative directory as the absolute one it is", function()
    assert.equal(cache_path.mutation_results(vim.fn.getcwd()), cache_path.mutation_results("."))
    assert.equal(cache_path.coverage_stats(vim.fn.getcwd()), cache_path.coverage_stats("."))
  end)
end)
