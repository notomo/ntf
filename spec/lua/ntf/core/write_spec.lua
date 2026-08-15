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

  it("closes the file it wrote", function()
    local path = helper.test_data:path("out.json")

    assert.is_false(helper.leaves_file_open(path, function()
      write.file(path, "written")
    end))
  end)
end)
