local ntf = require("ntf")
local describe, before_each, after_each, it, pending, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.pending, ntf.finally, ntf.assert
local walk = require("ntf.core.walk")
local path = require("ntf.core.path")
local helper = require("ntf.test.helper")

--- @param dir string
--- @param descend? fun(dir: string): boolean
--- @return string[] # what the walk handed to on_file, sorted
local function visited(dir, descend)
  local files = {}
  walk.files(dir, {
    descend = descend or function()
      return true
    end,
    on_file = function(file)
      table.insert(files, file)
    end,
  })
  table.sort(files)
  return files
end

describe("ntf.core.walk.files", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("visits the files of a directory and of the ones below it", function()
    local nested = helper.test_data:create_file("dir/sub/nested.lua", "")
    local top = helper.test_data:create_file("top.lua", "")

    local files = visited(helper.test_data.full_path)

    assert.same({ path.normalize(nested), path.normalize(top) }, files)
  end)

  it("leaves a directory unvisited when descend rejects it", function()
    helper.test_data:create_file("skipped/nested.lua", "")
    local top = helper.test_data:create_file("top.lua", "")

    local files = visited(helper.test_data.full_path, function(dir)
      return vim.fs.basename(dir) ~= "skipped"
    end)

    assert.same({ path.normalize(top) }, files)
  end)

  it("walks a directory named after an environment variable, not the one it names", function()
    vim.env.NTF_TEST_DIR = "expanded"
    finally(function()
      vim.env.NTF_TEST_DIR = nil
    end)
    local file = helper.test_data:create_file("$NTF_TEST_DIR/a.lua", "")
    helper.test_data:create_file("expanded/b.lua", "")

    local files = visited(helper.test_data:path("$NTF_TEST_DIR"))

    assert.same({ path.normalize(file) }, files)
  end)

  it("visits a symlinked file the same as the one it points at", function()
    if vim.fn.has("win32") == 1 then
      return pending("a symlink needs a privileged account on windows")
    end
    local file = helper.test_data:create_file("target.lua", "")
    local link = helper.test_data:path("link.lua")
    local ok, err = vim.uv.fs_symlink(file, link)
    if not ok then
      error(err)
    end

    local files = visited(helper.test_data.full_path)

    assert.same({ path.normalize(link), path.normalize(file) }, files)
  end)

  it("hands a symlinked directory over as an entry instead of walking into it", function()
    if vim.fn.has("win32") == 1 then
      return pending("a symlink needs a privileged account on windows")
    end
    local file = helper.test_data:create_file("dir/a.lua", "")
    local link = helper.test_data:path("link")
    local ok, err = vim.uv.fs_symlink(helper.test_data:path("dir"), link)
    if not ok then
      error(err)
    end

    local files = visited(helper.test_data.full_path)

    assert.same({ path.normalize(file), path.normalize(link) }, files)
  end)
end)
