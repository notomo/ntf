local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local instrument = require("ntf.core.coverage.instrument")
local cache_path = require("ntf.core.cache_path")
local helper = require("ntf.test.helper")

--- @param src string
--- @return any # what the source returns
--- @return table<integer, integer> # the hits it counted, by row
local function run(src)
  local counts = {}
  local chunk = assert(loadstring(instrument.transform(src), "@subject.lua"))
  return chunk(counts)(), counts
end

describe("ntf.core.coverage.instrument.transform", function()
  it("counts every statement as often as it runs", function()
    local src = table.concat({
      "local total = 0",
      "for i = 1, 3 do",
      "  total = total + i",
      "end",
      "return total",
    }, "\n")

    local total, counts = run(src)

    assert.equal(6, total)
    assert.same({ [1] = 1, [2] = 1, [3] = 3, [5] = 1 }, counts)
  end)

  it("counts a statement of a function only once the function is called", function()
    local src = table.concat({
      "local function f()",
      "  return 1",
      "end",
      "return f",
    }, "\n")

    local f, counts = run(src)

    assert.is_nil(counts[2])
    f()
    assert.equal(1, counts[2])
  end)

  it("counts each of the statements a single row holds", function()
    local src = "local a = 1 local b = 2 return a + b"

    local total, counts = run(src)

    assert.equal(3, total)
    assert.equal(3, counts[1])
  end)

  it("leaves every line of the source where it was", function()
    local src = table.concat({
      "local f = function()",
      "  return 1",
      "end",
      "return f",
    }, "\n")

    local f = run(src)

    assert.equal(1, debug.getinfo(f, "S").linedefined)
  end)

  it("leaves a long string holding Lua as it was written", function()
    local held = "local x = 1"
    local src = table.concat({
      "local s = [[",
      held,
      "]]",
      "return s",
    }, "\n")

    local s = run(src)

    assert.equal(held .. "\n", s)
  end)

  it("counts nothing in a source that holds no statement", function()
    local _, counts = run("-- nothing to run here")

    assert.same({}, counts)
  end)

  it("counts the module-level rows of a source ending without a newline", function()
    local _, counts = run("return 1")

    assert.same({ [1] = 1 }, counts)
  end)

  it("counts every row from one up, never a row below it", function()
    local _, counts = run("local x = 1\nreturn x")

    local rows = vim.tbl_keys(counts)
    table.sort(rows)
    assert.equal(1, rows[1])
  end)
end)

describe("ntf.core.coverage.instrument.chunk", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  --- @param name string
  --- @param content string
  --- @return string # the normalized path it was written to, its instrumented copy dropped at the end of the test
  local function source_file(name, content)
    local path = vim.fs.normalize(helper.test_data:create_file(name, content))
    finally(function()
      vim.fn.delete(cache_path.instrumented(path))
    end)
    return path
  end

  it("returns the body of the file, counting into the table it is called with", function()
    local path = source_file("subject.lua", "return 1")

    local counts = {}
    local body = assert(instrument.chunk(path))(counts)

    assert.equal(1, body())
    assert.same({ [1] = 1 }, counts)
  end)

  it("files an instrumented copy of the source it read", function()
    local path = source_file("subject.lua", "return 1")

    instrument.chunk(path)

    assert.equal(1, vim.fn.filereadable(cache_path.instrumented(path)))
  end)

  it("reads the copy an earlier run left for the same source", function()
    local path = source_file("subject.lua", "return 1")
    instrument.chunk(path)
    local copy = cache_path.instrumented(path)
    local reader = assert(io.open(copy, "r"))
    local left = reader:read("*a")
    reader:close()
    local writer = assert(io.open(copy, "w"))
    writer:write((left:gsub("__ntf_counts%[1%]", "__ntf_counts[7]")))
    writer:close()

    local counts = {}
    assert(instrument.chunk(path))(counts)()

    assert.same({ [7] = 1 }, counts)
  end)

  it("makes a copy of its own once the source has changed", function()
    local path = source_file("subject.lua", "return 1")
    instrument.chunk(path)

    helper.test_data:create_file("subject.lua", "local x = 1\nreturn x")
    local counts = {}
    assert(instrument.chunk(path))(counts)()

    assert.same({ [1] = 1, [2] = 1 }, counts)
  end)

  it("closes the source it read", function()
    local path = source_file("subject.lua", "return 1")

    assert.is_false(helper.leaves_file_open(path, function()
      instrument.chunk(path)
    end))
  end)

  it("returns nothing for a file that is not there", function()
    assert.is_nil(instrument.chunk(helper.test_data:path("missing.lua")))
  end)

  it("returns nothing for a file whose instrumented copy is no Lua", function()
    local shebang_is_no_lua_expression = "#!/usr/bin/env lua\nreturn 1"
    local path = source_file("subject.lua", shebang_is_no_lua_expression)

    assert.is_nil(instrument.chunk(path))
  end)
end)
