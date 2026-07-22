local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local discover = require("ntf.core.controller.discover")
local helper = require("ntf.test.helper")

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

  it("dedupes a file passed twice and one passed both directly and via its directory", function()
    local file = helper.test_data:create_file("dir/a_spec.lua", "")

    local files = discover.specs({ file, file, helper.test_data:path("dir") })

    assert.equal(1, #files)
    assert.match("a_spec%.lua$", files[1])
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
