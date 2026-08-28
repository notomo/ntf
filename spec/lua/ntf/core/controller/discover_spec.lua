local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local discover = require("ntf.core.controller.discover")
local helper = require("ntf.test.helper")
local path = require("ntf.core.path")

describe("ntf.core.controller.discover.specs", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("collects only *_spec.lua files under a directory, recursively and sorted", function()
    helper.test_data:create_file("dir/z_spec.lua", "")
    helper.test_data:create_file("dir/nested/a_spec.lua", "")
    helper.test_data:create_file("dir/plain.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") })

    assert.equal(2, #files)
    assert.match("a_spec%.lua$", files[1])
    assert.match("z_spec%.lua$", files[2])
  end)

  it("sorts the files, whatever order the paths name them", function()
    local a = helper.test_data:create_file("dir/a_spec.lua", "")
    local z = helper.test_data:create_file("dir/z_spec.lua", "")

    local files = discover.specs({ z, a })

    assert.same({ vim.fs.normalize(a), vim.fs.normalize(z) }, files)
  end)

  it("dedupes a file passed twice and one passed both directly and via its directory", function()
    local file = helper.test_data:create_file("dir/a_spec.lua", "")

    local files = discover.specs({ file, file, helper.test_data:path("dir") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("collects a spec file named on its own, with no directory to glob", function()
    local file = helper.test_data:create_file("dir/a_spec.lua", "")

    local files = discover.specs({ file })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("keeps collecting the specs a wildignore would otherwise hide", function()
    local saved = vim.o.wildignore
    finally(function()
      vim.o.wildignore = saved
    end)
    vim.o.wildignore = "*_spec.lua"
    helper.test_data:create_file("dir/a_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") })

    assert.equal(1, #files)
  end)

  it("does not descend into a dot-prefixed directory", function()
    helper.test_data:create_file("dir/a_spec.lua", "")
    helper.test_data:create_file("dir/.hidden/b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("does not descend into a dot-prefixed directory nested under another directory", function()
    helper.test_data:create_file("dir/nested/a_spec.lua", "")
    helper.test_data:create_file("dir/nested/.hidden/b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("does not collect a dot-prefixed spec file", function()
    helper.test_data:create_file("dir/a_spec.lua", "")
    helper.test_data:create_file("dir/.b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("does not collect a directory named like a spec file", function()
    helper.test_data:create_dir("dir/looks_like_spec.lua")

    local files = discover.specs({ helper.test_data:path("dir") })

    assert.same({}, files)
  end)

  it("collects the specs under a dot-prefixed directory named as a path, which discovery would have skipped", function()
    helper.test_data:create_file(".hidden/a_spec.lua", "")

    local files = discover.specs({ helper.test_data:path(".hidden") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("collects the specs under a directory path that walks up and back down", function()
    local file = helper.test_data:create_file("dir/a_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir/../dir") })

    assert.same({ path.normalize(file) }, files)
  end)

  it("collects the specs under a bracketed directory, not the ones the brackets would have matched", function()
    local file = helper.test_data:create_file("pr[o]j/a_spec.lua", "")
    helper.test_data:create_file("proj/b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("pr[o]j") })

    assert.same({ path.normalize(file) }, files)
  end)

  it("collects the specs under a braced directory", function()
    local file = helper.test_data:create_file("a{b}/a_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("a{b}") })

    assert.same({ path.normalize(file) }, files)
  end)

  it("collects the specs under a directory named after an environment variable, not the ones it names", function()
    vim.env.NTF_TEST_DIR = "expanded"
    finally(function()
      vim.env.NTF_TEST_DIR = nil
    end)
    local file = helper.test_data:create_file("$NTF_TEST_DIR/a_spec.lua", "")
    helper.test_data:create_file("expanded/b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("$NTF_TEST_DIR") })

    assert.same({ path.normalize(file) }, files)
  end)

  it("errors, unprefixed, on a readable file that is not a spec", function()
    local file = helper.test_data:create_file("dir/plain.lua", "")

    local ok, err = pcall(discover.specs, { file })

    assert.is_false(ok)
    assert.equal("not a *_spec.lua file: " .. file, err)
  end)

  it("errors, unprefixed, on a path that is neither a directory nor a readable file", function()
    local missing = helper.test_data:path("dir/missing_spec.lua")

    local ok, err = pcall(discover.specs, { missing })

    assert.is_false(ok)
    assert.equal("path not found: " .. missing, err)
  end)

  it("skips an excluded file but keeps the rest", function()
    helper.test_data:create_file("dir/a_spec.lua", "")
    local skipped = helper.test_data:create_file("dir/b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") }, { skipped })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)

  it("skips every spec under an excluded directory", function()
    helper.test_data:create_file("dir/a_spec.lua", "")
    helper.test_data:create_file("dir/nested/b_spec.lua", "")

    local files = discover.specs({ helper.test_data:path("dir") }, { helper.test_data:path("dir/nested") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
  end)
end)

describe("ntf.core.controller.discover.default_paths", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("names the spec directory the project holds", function()
    helper.test_data:create_dir("spec")
    helper.test_data:cd("")

    assert.same({ "spec" }, discover.default_paths())
  end)

  it("names nothing where the project holds no spec directory", function()
    helper.test_data:cd("")

    assert.same({}, discover.default_paths())
  end)
end)

describe("ntf.core.controller.discover.holds_every_spec", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("holds every spec where the files are the ones the spec directory gives", function()
    helper.test_data:create_file("spec/a_spec.lua", "")
    helper.test_data:cd("")

    assert.is_true(discover.holds_every_spec(discover.specs({ "spec" })))
  end)

  it("holds every spec where the files are more than the spec directory gives", function()
    helper.test_data:create_file("spec/a_spec.lua", "")
    helper.test_data:create_file("other/b_spec.lua", "")
    helper.test_data:cd("")

    assert.is_true(discover.holds_every_spec(discover.specs({ "spec", "other" })))
  end)

  it("holds only part of them where a spec of the directory is missing from the files", function()
    helper.test_data:create_file("spec/a_spec.lua", "")
    helper.test_data:create_file("spec/b_spec.lua", "")
    helper.test_data:cd("")

    assert.is_false(discover.holds_every_spec(discover.specs({ "spec/a_spec.lua" })))
  end)

  it("holds only part of them where the project has no spec directory to answer with", function()
    helper.test_data:create_file("other/a_spec.lua", "")
    helper.test_data:cd("")

    assert.is_false(discover.holds_every_spec(discover.specs({ "other" })))
  end)
end)
