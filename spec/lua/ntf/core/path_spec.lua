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
