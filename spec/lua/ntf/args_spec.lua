local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local args = require("ntf.cli.args")

describe("ntf.cli.args.parse", function()
  it("parses --filter into opts.filter", function()
    local opts = args.parse({ "--filter=adds", "spec" })

    assert.equal("adds", opts.filter)
  end)

  it("leaves opts.filter nil when --filter is absent", function()
    local opts = args.parse({ "spec" })

    assert.equal(nil, opts.filter)
  end)

  it("rejects a malformed --filter Lua pattern", function()
    local err = args.parse({ "--filter=%", "spec" })

    assert.match("invalid %-%-filter pattern", err)
  end)
end)
