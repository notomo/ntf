local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local cache = require("ntf.core.cache")
local absolute = require("ntf.core.path").absolute
local helper = require("ntf.test.helper")

--- @param path string an absolute path
--- @return string # the name a cache file for it is filed under, before the extension
local function escaped(path)
  return (absolute(path):gsub("[/\\:]", "%%"))
end

--- @return string # the cache root the test cleans
local function root()
  return helper.test_data:path("ntf")
end

--- @param kind string
--- @param name string
--- @return string # the cache file it created, empty
local function cached(kind, name)
  return helper.test_data:create_file(vim.fs.joinpath("ntf", kind, name), "")
end

--- @param cleaned NtfCacheCleaned[]
--- @param name string
--- @return NtfCacheCleaned
local function of(cleaned, name)
  for _, entry in ipairs(cleaned) do
    if entry.name == name then
      return entry
    end
  end
  error("no entry for " .. name)
end

describe("ntf.core.cache.clean", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("removes a file named for a working directory that is gone, keeping one whose directory stands", function()
    local standing = helper.test_data:create_dir("project")
    local gone = helper.test_data:path("gone")
    local kept = cached("schedule", escaped(standing) .. ".json")
    local removed = cached("schedule", escaped(gone) .. ".json")

    local cleaned = cache.clean(root())

    assert.equal(1, vim.fn.filereadable(kept))
    assert.equal(0, vim.fn.filereadable(removed))
    assert.equal(1, of(cleaned, "schedule").removed)
    assert.equal(1, of(cleaned, "schedule").kept)
  end)

  it("judges the mutation results and the coverage stats the same way", function()
    local gone = helper.test_data:path("gone")
    cached("mutation", escaped(gone) .. ".json")
    cached("coverage", escaped(gone) .. ".out")

    local cleaned = cache.clean(root())

    assert.equal(1, of(cleaned, "mutation").removed)
    assert.equal(1, of(cleaned, "coverage").removed)
  end)

  it("removes the instrumented copy of a source that is gone, keeping one whose source stands", function()
    local standing = helper.test_data:create_file("lua/mod.lua", "return 1")
    local gone = helper.test_data:path("lua/gone.lua")
    local kept = cached("instrumented", escaped(standing) .. ".instrumented")
    local removed = cached("instrumented", escaped(gone) .. ".instrumented")

    local cleaned = cache.clean(root())

    assert.equal(1, vim.fn.filereadable(kept))
    assert.equal(0, vim.fn.filereadable(removed))
    assert.equal(1, of(cleaned, "instrumented").removed)
    assert.equal(1, of(cleaned, "instrumented").kept)
  end)

  it("removes every payload, which a worker that took its own has already removed", function()
    local left = cached("payload", ("a"):rep(32) .. ".json")

    local cleaned = cache.clean(root())

    assert.equal(0, vim.fn.filereadable(left))
    assert.equal(1, of(cleaned, "payload").removed)
    assert.equal(0, of(cleaned, "payload").kept)
  end)

  it("leaves a file of another extension, and a directory, where it found them", function()
    local other = cached("schedule", escaped(helper.test_data:path("gone")) .. ".txt")
    local dir = helper.test_data:create_dir("ntf/schedule/nested")

    local cleaned = cache.clean(root())

    assert.equal(1, vim.fn.filereadable(other))
    assert.equal(1, vim.fn.isdirectory(dir))
    assert.same(
      { removed = 0, kept = 0 },
      { removed = of(cleaned, "schedule").removed, kept = of(cleaned, "schedule").kept }
    )
  end)

  it("counts a file it could not remove as kept", function()
    local gone = helper.test_data:path("gone")
    local held = cached("schedule", escaped(gone) .. ".json")
    local remove = os.remove
    --- @diagnostic disable-next-line: duplicate-set-field
    os.remove = function(file)
      if file == held then
        return nil, "held"
      end
      return remove(file)
    end
    ntf.finally(function()
      os.remove = remove
    end)

    local cleaned = cache.clean(root())

    assert.equal(0, of(cleaned, "schedule").removed)
    assert.equal(1, of(cleaned, "schedule").kept)
  end)

  it("reports every kind as empty where nothing was ever cached", function()
    local cleaned = cache.clean(helper.test_data:path("never"))

    assert.equal(5, #cleaned)
    for _, entry in ipairs(cleaned) do
      assert.equal(0, entry.removed + entry.kept)
    end
  end)
end)

describe("ntf.core.cache.report", function()
  it("names the root, then one line per kind with what was removed of how many and why", function()
    local text = cache.report("/cache/ntf", {
      { name = "schedule", removed = 1, kept = 2, reason = "named for a working directory that is gone" },
      { name = "payload", removed = 0, kept = 0, reason = "left by workers that never took them" },
    })

    assert.equal(
      table.concat({
        "/cache/ntf",
        "  schedule: removed 1 of 3 (named for a working directory that is gone)",
        "  payload: removed 0 of 0 (left by workers that never took them)",
        "",
      }, "\n"),
      text
    )
  end)
end)
