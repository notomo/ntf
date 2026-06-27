local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local args = require("ntf.core.controller.args")
local helper = require("ntf.test.helper")

describe("ntf.core.controller.args.parse", function()
  it("parses --filter into opts.filter", function()
    local opts = args.parse({ "--filter=adds", "spec" })

    assert.equal("adds", opts.filter)
  end)

  it("leaves opts.filter nil when --filter is absent", function()
    local opts = args.parse({ "spec" })

    assert.equal(nil, opts.filter)
  end)

  it("accepts the space-separated --filter VALUE form", function()
    local opts = args.parse({ "--filter", "adds", "spec" })

    assert.equal("adds", opts.filter)
    assert.equal("spec", opts.paths[1])
  end)

  it("does not swallow a path that looks like a value-flag name", function()
    local opts = args.parse({ "--jobs", "2", "spec" })

    assert.equal(2, opts.jobs)
    assert.equal("spec", opts.paths[1])
  end)

  it("errors when a value-taking flag has no value", function()
    local err = args.parse({ "spec", "--filter" })

    assert.match("missing value for %-%-filter", err)
  end)

  it("rejects a malformed --filter Lua pattern", function()
    local err = args.parse({ "--filter=%", "spec" })

    assert.match("invalid %-%-filter pattern", err)
  end)

  it("defaults --timeout to 60000ms", function()
    local opts = args.parse({ "spec" })

    assert.equal(60000, opts.timeout)
  end)

  it("parses --timeout into opts.timeout", function()
    local opts = args.parse({ "--timeout=1500", "spec" })

    assert.equal(1500, opts.timeout)
  end)

  it("accepts --timeout=0 to disable the worker timeout", function()
    local opts = args.parse({ "--timeout=0", "spec" })

    assert.equal(0, opts.timeout)
  end)

  it("rejects a non-numeric --timeout", function()
    local err = args.parse({ "--timeout=soon", "spec" })

    assert.match("invalid %-%-timeout value", err)
  end)

  it("rejects a negative --timeout", function()
    local err = args.parse({ "--timeout=-5", "spec" })

    assert.match("invalid %-%-timeout value", err)
  end)

  it("enables shuffle without a seed for bare --shuffle", function()
    local opts = args.parse({ "--shuffle", "spec" })

    assert.equal(true, opts.shuffle)
    assert.equal(nil, opts.seed)
    assert.equal("spec", opts.paths[1])
  end)

  it("fixes the shuffle order with --shuffle=SEED", function()
    local opts = args.parse({ "--shuffle=42", "spec" })

    assert.equal(true, opts.shuffle)
    assert.equal(42, opts.seed)
  end)

  it("does not treat a following path as the shuffle seed", function()
    local opts = args.parse({ "--shuffle", "42" })

    assert.equal(true, opts.shuffle)
    assert.equal(nil, opts.seed)
    assert.equal("42", opts.paths[1])
  end)

  it("rejects a non-numeric --shuffle seed", function()
    local err = args.parse({ "--shuffle=soon", "spec" })

    assert.match("invalid %-%-shuffle seed", err)
  end)

  describe("with no paths", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("defaults to spec when a ./spec directory exists", function()
      helper.test_data:create_dir("spec")
      helper.test_data:cd("")

      local opts = args.parse({})

      assert.equal("spec", opts.paths[1])
    end)

    it("errors when there is no ./spec directory", function()
      helper.test_data:cd("")

      local err = args.parse({})

      assert.match("no spec paths given", err)
    end)
  end)
end)
