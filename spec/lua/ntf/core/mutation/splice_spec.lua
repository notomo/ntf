local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")

describe("ntf.core.mutation.splice.apply", function()
  it("splices the replacement into the source", function()
    local src = [[local _ = a == b]]
    local site = operators.enumerate(src)[1]

    assert.equal([[local _ = a ~= b]], splice.apply(src, site))
  end)

  it("returns nil when the source no longer matches the site", function()
    local site = operators.enumerate([[local _ = a == b]])[1]

    assert.is_nil(splice.apply([[local _ = a < b]], site))
  end)
end)
