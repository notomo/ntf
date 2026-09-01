local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local write = require("ntf.core.write")
local helper = require("ntf.test.helper")

describe("ntf.core.write", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("creates the directories the path names, which nothing else makes", function()
    local path = helper.test_data:path("cache/ntf/out.json")

    write.file(path, "written")

    assert.same({ "written" }, vim.fn.readfile(path))
  end)

  it("replaces what the file held", function()
    local path = helper.test_data:create_file("out.json", "old")

    write.file(path, "new")

    assert.same({ "new" }, vim.fn.readfile(path))
  end)

  it("leaves no temporary file beside the one it wrote", function()
    local dir = helper.test_data:path("cache")
    write.file(vim.fs.joinpath(dir, "out.json"), "written")

    assert.same({ "out.json" }, vim.fn.readdir(dir))
  end)

  it("raises what refused the rename, leaving no temporary file beside the target", function()
    local dir = helper.test_data:create_dir("cache")
    local taken = helper.test_data:create_dir("cache/out.json")
    helper.test_data:create_file("cache/out.json/held", "a directory holding a file takes no rename")

    local ok, err = pcall(write.file, taken, "written")

    assert.is_false(ok)
    assert.match(vim.pesc(taken) .. "$", err)
    assert.same({ "out.json" }, vim.fn.readdir(dir))
  end)

  it("closes the temporary file it wrote before renaming it into place", function()
    local path = helper.test_data:path("out.json")
    local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())

    assert.is_false(helper.leaves_file_open(tmp, function()
      write.file(path, "written")
    end))
  end)
end)
