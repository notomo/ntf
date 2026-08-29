local ntf = require("ntf")
local describe, it, finally, assert = ntf.describe, ntf.it, ntf.finally, ntf.assert
local path = require("ntf.core.path")

--- @type string what an absolute path starts with here: on Windows the drive, without which a path from the root alone is resolved against the drive the run is on; nothing elsewhere
local drive = vim.fn.getcwd():match("^%a:") or ""

describe("ntf.core.path.is_hidden", function()
  it("is true for a dot-prefixed name", function()
    assert.is_true(path.is_hidden(".hidden"))
  end)

  it("is false for a plain name", function()
    assert.is_false(path.is_hidden("plain"))
  end)

  it("reads the last component, not the ones above it", function()
    assert.is_true(path.is_hidden("plain/.hidden"))
    assert.is_false(path.is_hidden(".hidden/plain"))
  end)
end)

describe("ntf.core.path.normalize", function()
  it("spells the separators as slashes", function()
    assert.equal("C:/dir/sub", path.normalize("C:\\dir\\sub"))
  end)

  it("upper-cases a windows drive letter, as the path of a discovered file carries", function()
    assert.equal("C:/dir", path.normalize("c:/dir"))
  end)

  it("drops a trailing separator, which a directory path carries", function()
    assert.equal("/dir/sub", path.normalize("/dir/sub/"))
  end)

  it("keeps the root, which is a separator on its own", function()
    assert.equal("/", path.normalize("/"))
  end)

  it("folds a current-directory component, so one file never gets two keys", function()
    assert.equal("/dir/sub", path.normalize("/dir/./sub"))
  end)

  it("folds a parent component into the component above it", function()
    assert.equal("/dir/sub", path.normalize("/dir/other/../sub"))
  end)

  it("folds the only component above it, leaving the root", function()
    assert.equal("/", path.normalize("/dir/.."))
  end)

  it("folds the component above it, not the one before that", function()
    assert.equal("..", path.normalize("../dir/.."))
  end)

  it("folds a repeated separator", function()
    assert.equal("/dir/sub", path.normalize("/dir//sub"))
  end)

  it("drops a parent component of the root, which has nothing above it", function()
    assert.equal("/dir", path.normalize("/../dir"))
  end)

  it("keeps the leading parent components of a relative path, which is not rooted anywhere yet", function()
    assert.equal("../../dir", path.normalize("../../dir"))
  end)

  it("keeps a component named after an environment variable, which is a directory name like any other", function()
    vim.env.NTF_TEST_DIR = "expanded"
    finally(function()
      vim.env.NTF_TEST_DIR = nil
    end)

    assert.equal("/dir/$NTF_TEST_DIR/sub", path.normalize("/dir/$NTF_TEST_DIR/sub"))
  end)
end)

describe("ntf.core.path.absolute", function()
  it("resolves a relative path against the working directory", function()
    assert.equal(path.normalize(vim.fn.getcwd()) .. "/dir/sub", path.absolute("dir/sub"))
  end)

  it("keeps an absolute path, without its trailing separator", function()
    assert.equal(drive .. "/dir/sub", path.absolute(drive .. "/dir/sub/"))
  end)

  it("names a directory named after an environment variable, not the one it names", function()
    vim.env.NTF_TEST_DIR = "expanded"
    finally(function()
      vim.env.NTF_TEST_DIR = nil
    end)

    assert.equal(drive .. "/dir/$NTF_TEST_DIR", path.absolute(drive .. "/dir/$NTF_TEST_DIR"))
  end)
end)

describe("ntf.core.path.relative", function()
  local dir = drive .. "/dir"

  it("cuts the directory off a path below it", function()
    assert.equal("spec/x_spec.lua", path.relative(dir .. "/spec/x_spec.lua", dir))
  end)

  it("keeps the path of a sibling whose name merely starts with the directory", function()
    local sibling = drive .. "/dir-other/spec/x_spec.lua"

    assert.equal(sibling, path.relative(sibling, dir))
  end)

  it("keeps the directory itself, which sits at no depth below it", function()
    assert.equal(dir, path.relative(dir, dir))
  end)

  it("keeps a path the directory does not hold at all", function()
    local elsewhere = drive .. "/elsewhere/x_spec.lua"

    assert.equal(elsewhere, path.relative(elsewhere, dir))
  end)

  it("normalizes the path before cutting, so an unnormalized one is still recognized as below", function()
    assert.equal("spec/x_spec.lua", path.relative(dir .. "//spec/./x_spec.lua", dir))
  end)

  it("normalizes the directory too, which a caller may hand over with its trailing separator", function()
    assert.equal("spec/x_spec.lua", path.relative(dir .. "/spec/x_spec.lua", dir .. "/"))
  end)

  it("resolves a relative directory against the working directory, which is the place it names", function()
    local file = vim.fs.joinpath(vim.fn.getcwd(), "lua", "ntf", "init.lua")

    assert.equal("ntf/init.lua", path.relative(file, "lua"))
  end)
end)
