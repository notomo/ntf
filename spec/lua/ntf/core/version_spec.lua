local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local version = require("ntf.core.version")

describe("ntf.core.version", function()
  it("takes 0.12.0 and everything after it", function()
    assert.is_nil(version.unsupported(vim.version.parse("0.12.0")))
    assert.is_nil(version.unsupported(vim.version.parse("0.12.1")))
    assert.is_nil(version.unsupported(vim.version.parse("0.13.0-dev")))
    assert.is_nil(version.unsupported(vim.version.parse("1.0.0")))
  end)

  it("turns away a version before 0.12.0, naming both it and the requirement", function()
    local message = version.unsupported(vim.version.parse("0.11.4"))

    assert.match("0%.12%.0 or later", message)
    assert.match("this one is 0%.11%.4", message)
  end)

  it("turns away a prerelease of 0.12.0, which comes before its release", function()
    assert.match("this one is 0%.12%.0%-dev", version.unsupported(vim.version.parse("0.12.0-dev")))
  end)

  it("says which environment variable names the binary to run instead", function()
    assert.match("NTF_NVIM", version.unsupported(vim.version.parse("0.11.4")))
  end)
end)
