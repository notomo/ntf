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

  it("leaves coverage off by default", function()
    local opts = args.parse({ "spec" })

    assert.equal(false, opts.coverage)
  end)

  it("enables coverage with the default stats file for bare --coverage", function()
    local opts = args.parse({ "--coverage", "spec" })

    assert.equal(true, opts.coverage)
    assert.equal("luacov.stats.out", opts.coverage_file)
    assert.equal("spec", opts.paths[1])
  end)

  it("overrides the stats file with --coverage=FILE", function()
    local opts = args.parse({ "--coverage=cov.out", "spec" })

    assert.equal(true, opts.coverage)
    assert.equal("cov.out", opts.coverage_file)
  end)

  it("does not treat a following path as the coverage file", function()
    local opts = args.parse({ "--coverage", "spec" })

    assert.equal(true, opts.coverage)
    assert.equal("luacov.stats.out", opts.coverage_file)
    assert.equal("spec", opts.paths[1])
  end)

  it("leaves listing off by default", function()
    local opts = args.parse({ "spec" })

    assert.is_false(opts.list)
  end)

  it("parses --list into opts.list", function()
    local opts = args.parse({ "--list", "spec" })

    assert.is_true(opts.list)
    assert.equal("spec", opts.paths[1])
  end)

  it("parses -h and --help into opts.help", function()
    assert.is_true(args.parse({ "-h" }).help)
    assert.is_true(args.parse({ "--help" }).help)
  end)

  it("rejects an unknown option", function()
    local err = args.parse({ "-x", "spec" })

    assert.match("unknown option: %-x", err)
  end)

  it("aligns the longest flag name two spaces from its description in usage", function()
    local longest = args.flags[1]
    for _, flag in ipairs(args.flags) do
      if #flag.name > #longest.name then
        longest = flag
      end
    end

    local lines = vim.split(args.usage(), "\n", { plain = true })

    assert.is_true(vim.tbl_contains(lines, ("  %s  %s"):format(longest.name, longest.description)))
  end)

  describe("--test-hook", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("parses --test-hook into opts.test_hook", function()
      local path = helper.test_data:create_file("test_hook.lua", "return {}")

      local opts = args.parse({ "--test-hook=" .. path, "spec" })

      assert.equal(path, opts.test_hook)
    end)

    it("errors when the --test-hook module does not exist", function()
      local err = args.parse({ "--test-hook=/no/such/hook.lua", "spec" })

      assert.match("%-%-test%-hook module not found", err)
    end)
  end)

  describe("--global-hook", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("parses --global-hook into opts.global_hook", function()
      local path = helper.test_data:create_file("global_hook.lua", "return {}")

      local opts = args.parse({ "--global-hook=" .. path, "spec" })

      assert.equal(path, opts.global_hook)
    end)

    it("leaves opts.global_hook nil when --global-hook is absent", function()
      local opts = args.parse({ "spec" })

      assert.equal(nil, opts.global_hook)
    end)

    it("accepts the space-separated --global-hook VALUE form", function()
      local path = helper.test_data:create_file("global_hook.lua", "return {}")

      local opts = args.parse({ "--global-hook", path, "spec" })

      assert.equal(path, opts.global_hook)
      assert.equal("spec", opts.paths[1])
    end)

    it("errors when the --global-hook module does not exist", function()
      local err = args.parse({ "--global-hook=/no/such/hook.lua", "spec" })

      assert.match("%-%-global%-hook module not found", err)
    end)
  end)

  describe("--exclude-code", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("collects every occurrence", function()
      local vendor = helper.test_data:create_dir("lua/vendor")
      local test = helper.test_data:create_dir("lua/test")

      local opts = args.parse({ "--coverage", "--exclude-code=" .. vendor, "--exclude-code=" .. test, "spec" })

      assert.same({ vendor, test }, opts.exclude_code)
    end)

    it("errors when the path does not exist", function()
      local err = args.parse({ "--coverage", "--exclude-code=/no/such/dir", "spec" })

      assert.match("%-%-exclude%-code path not found", err)
    end)

    it("errors without something to exclude the code from", function()
      local vendor = helper.test_data:create_dir("lua/vendor")

      local err = args.parse({ "--exclude-code=" .. vendor, "spec" })

      assert.match("%-%-exclude%-code requires %-%-coverage or %-%-mutation", err)
    end)
  end)

  describe("--exclude-spec", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("collects every occurrence", function()
      local a = helper.test_data:create_file("a_spec.lua", "")
      local dir = helper.test_data:create_dir("nested")

      local opts = args.parse({ "--exclude-spec=" .. a, "--exclude-spec=" .. dir, "spec" })

      assert.same({ a, dir }, opts.exclude_spec)
    end)

    it("errors when the path does not exist", function()
      local err = args.parse({ "--exclude-spec=/no/such/dir", "spec" })

      assert.match("%-%-exclude%-spec path not found", err)
    end)
  end)

  describe("--mutation", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("is off by default", function()
      local opts = args.parse({ "spec" })

      assert.is_false(opts.mutation)
      assert.equal("ntf-mutation.json", opts.mutation_results)
    end)

    it("takes an optional path to restrict the mutated files", function()
      local dir = helper.test_data:create_dir("lua")

      local opts = args.parse({ "--mutation=" .. dir, "spec" })

      assert.is_true(opts.mutation)
      assert.equal(dir, opts.mutation_path)
    end)

    it("reads the results file", function()
      local opts = args.parse({ "--mutation", "--mutation-results=out.json", "spec" })

      assert.equal("out.json", opts.mutation_results)
    end)

    it("errors when the --mutation path does not exist", function()
      local err = args.parse({ "--mutation=/no/such/dir", "spec" })

      assert.match("%-%-mutation path not found", err)
    end)

    it("gates on every category for bare --mutation-strict", function()
      local opts = args.parse({ "--mutation", "--mutation-strict", "spec" })

      assert.same({ survived = true, no_coverage = true }, opts.mutation_strict)
    end)

    it("treats --mutation-strict= with an empty value as bare --mutation-strict", function()
      local opts = args.parse({ "--mutation", "--mutation-strict=", "spec" })

      assert.same({ survived = true, no_coverage = true }, opts.mutation_strict)
    end)

    it("restricts the gate to the listed categories", function()
      assert.same(
        { survived = true },
        args.parse({ "--mutation", "--mutation-strict=survived", "spec" }).mutation_strict
      )
      assert.same(
        { no_coverage = true },
        args.parse({ "--mutation", "--mutation-strict=no_coverage", "spec" }).mutation_strict
      )
      assert.same(
        { survived = true, no_coverage = true },
        args.parse({ "--mutation", "--mutation-strict=survived,no_coverage", "spec" }).mutation_strict
      )
    end)

    it("errors on an unknown --mutation-strict category", function()
      local err = args.parse({ "--mutation", "--mutation-strict=killed", "spec" })

      assert.match("invalid %-%-mutation%-strict category: killed", err)
    end)

    it("leaves the gate disabled without --mutation-strict", function()
      assert.is_nil(args.parse({ "--mutation", "spec" }).mutation_strict)
    end)

    it("treats --mutation= with an empty value as bare --mutation", function()
      local opts = args.parse({ "--mutation=", "spec" })

      assert.is_true(opts.mutation)
      assert.is_nil(opts.mutation_path)
    end)

    it("leaves the matrix uncapped for bare --mutation-matrix", function()
      local opts = args.parse({ "--mutation", "--mutation-matrix", "spec" })

      assert.equal(math.huge, opts.mutation_matrix)
    end)

    it("treats --mutation-matrix= with an empty value as bare --mutation-matrix", function()
      local opts = args.parse({ "--mutation", "--mutation-matrix=", "spec" })

      assert.equal(math.huge, opts.mutation_matrix)
    end)

    it("reads the cap from --mutation-matrix=N", function()
      assert.equal(1, args.parse({ "--mutation", "--mutation-matrix=1", "spec" }).mutation_matrix)
      assert.equal(50, args.parse({ "--mutation", "--mutation-matrix=50", "spec" }).mutation_matrix)
    end)

    it("errors on a --mutation-matrix cap below one test", function()
      assert.match("invalid %-%-mutation%-matrix value", args.parse({ "--mutation", "--mutation-matrix=0", "spec" }))
      assert.match("invalid %-%-mutation%-matrix value", args.parse({ "--mutation", "--mutation-matrix=x", "spec" }))
    end)

    it("records only the first killer without --mutation-matrix", function()
      assert.is_nil(args.parse({ "--mutation", "spec" }).mutation_matrix)
    end)

    it("errors when --mutation-matrix alone is given without --mutation", function()
      local err = args.parse({ "--mutation-matrix", "spec" })

      assert.match("require %-%-mutation", err)
    end)

    it("reads the baseline file path", function()
      local file = helper.test_data:create_file("baseline.json", "{}")

      local opts = args.parse({ "--mutation", "--mutation-baseline=" .. file, "spec" })

      assert.equal(file, opts.mutation_baseline)
    end)

    it("errors when the --mutation-baseline file does not exist", function()
      local err = args.parse({ "--mutation", "--mutation-baseline=/no/such.json", "spec" })

      assert.match("%-%-mutation%-baseline file not found", err)
    end)

    it("errors when the mutation flags are given without --mutation", function()
      local err = args.parse({ "--mutation-strict", "spec" })

      assert.match("require %-%-mutation", err)
    end)

    it("errors when --mutation-baseline alone is given without --mutation", function()
      local file = helper.test_data:create_file("baseline.json", "{}")

      local err = args.parse({ "--mutation-baseline=" .. file, "spec" })

      assert.match("require %-%-mutation", err)
    end)

    it("errors when --mutation-results alone is given without --mutation", function()
      local err = args.parse({ "--mutation-results=out.json", "spec" })

      assert.match("require %-%-mutation", err)
    end)
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
