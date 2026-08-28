local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local path = require("ntf.core.path")

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
end)
