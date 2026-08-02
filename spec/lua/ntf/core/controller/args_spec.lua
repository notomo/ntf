local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local args = require("ntf.core.controller.args")
local helper = require("ntf.test.helper")

--- @param argv string[]
local command_of = function(argv)
  local chain = args.resolve(argv)
  return chain[#chain]
end

describe("ntf.core.controller.args.parse", function()
  describe("commands", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("runs the tests when no command is named", function()
      local opts = args.parse({ "spec" })

      assert.equal("run", opts.command)
      assert.same({ "spec" }, opts.paths)
    end)

    it("takes the leading token as the command", function()
      local opts = args.parse({ "list", "spec" })

      assert.equal("list", opts.command)
      assert.same({ "spec" }, opts.paths)
    end)

    it("descends into a subcommand", function()
      local file = helper.test_data:create_file("mutation.json", "{}")

      assert.equal("mutation.list", args.parse({ "mutation", "list", "spec" }).command)
      assert.equal(
        "mutation.verify-baseline",
        args.parse({ "mutation", "verify-baseline", "--config=" .. file, "spec" }).command
      )
    end)

    it("takes the default subcommand when the next token names none", function()
      assert.equal("mutation.run", args.parse({ "mutation", "spec" }).command)
      assert.equal("mutation.run", args.parse({ "mutation", "--strict", "spec" }).command)
    end)

    it("keeps a path that names a command, which the explicit run command is for", function()
      local opts = args.parse({ "run", "list" })

      assert.equal("run", opts.command)
      assert.same({ "list" }, opts.paths)
    end)

    it("takes a command name after a path as another path", function()
      local opts = args.parse({ "spec", "list" })

      assert.equal("run", opts.command)
      assert.same({ "spec", "list" }, opts.paths)
    end)

    it("rejects a flag the command does not take", function()
      local err = args.parse({ "list", "--coverage", "spec" })

      assert.match("unknown option: %-%-coverage", err)
    end)

    it("rejects a mutation flag outside the mutation commands", function()
      assert.match("unknown option: %-%-strict", args.parse({ "--strict", "spec" }))
      assert.match("unknown option: %-%-target", args.parse({ "list", "--target=lua", "spec" }))
    end)

    it("rejects a scoring flag on a command that scores nothing", function()
      assert.match("unknown option: %-%-results", args.parse({ "mutation", "list", "--results=out.json", "spec" }))
      assert.match("unknown option: %-%-strict", args.parse({ "mutation", "verify-baseline", "--strict", "spec" }))
    end)
  end)

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

  it("keeps an empty --filter value as the pattern every test matches", function()
    local opts = args.parse({ "--filter=", "spec" })

    assert.equal("", opts.filter)
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

  it("parses -h and --help into opts.help", function()
    assert.is_true(args.parse({ "-h" }).help)
    assert.is_true(args.parse({ "--help" }).help)
  end)

  it("rejects an unknown option", function()
    local err = args.parse({ "-x", "spec" })

    assert.match("unknown option: %-x", err)
  end)

  it("rejects a value given to a flag that takes none", function()
    local err = args.parse({ "mutation", "--verify-baseline=yes", "spec" })

    assert.match("unknown option: %-%-verify%-baseline=yes", err)
  end)

  it("keeps the given paths instead of defaulting to spec", function()
    assert.same({ "given/path" }, args.parse({ "given/path" }).paths)
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

      assert.match("%-%-exclude%-code requires %-%-coverage", err)
    end)

    it("needs nothing else under the mutation commands, which always measure", function()
      local vendor = helper.test_data:create_dir("lua/vendor")

      local opts = args.parse({ "mutation", "--exclude-code=" .. vendor, "spec" })

      assert.same({ vendor }, opts.exclude_code)
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

  describe("mutation", function()
    before_each(helper.before_each)
    after_each(helper.after_each)

    it("writes to the default results file", function()
      local opts = args.parse({ "mutation", "spec" })

      assert.equal("ntf-mutation.json", opts.mutation_results)
    end)

    it("reads the results file", function()
      local opts = args.parse({ "mutation", "--results=out.json", "spec" })

      assert.equal("out.json", opts.mutation_results)
    end)

    it("mutates every measured file without --target", function()
      local opts = args.parse({ "mutation", "spec" })

      assert.is_nil(opts.mutation_target)
    end)

    it("takes --target to restrict the mutated files", function()
      local dir = helper.test_data:create_dir("lua")

      local opts = args.parse({ "mutation", "--target=" .. dir, "spec" })

      assert.equal(dir, opts.mutation_target)
    end)

    it("errors when the --target path does not exist", function()
      local err = args.parse({ "mutation", "--target=/no/such/dir", "spec" })

      assert.match("%-%-target path not found", err)
    end)

    it("gates on every category for bare --strict", function()
      local opts = args.parse({ "mutation", "--strict", "spec" })

      assert.same({ survived = true, no_coverage = true }, opts.mutation_strict)
    end)

    it("treats --strict= with an empty value as bare --strict", function()
      local opts = args.parse({ "mutation", "--strict=", "spec" })

      assert.same({ survived = true, no_coverage = true }, opts.mutation_strict)
    end)

    it("restricts the gate to the listed categories", function()
      assert.same({ survived = true }, args.parse({ "mutation", "--strict=survived", "spec" }).mutation_strict)
      assert.same({ no_coverage = true }, args.parse({ "mutation", "--strict=no_coverage", "spec" }).mutation_strict)
      assert.same(
        { survived = true, no_coverage = true },
        args.parse({ "mutation", "--strict=survived,no_coverage", "spec" }).mutation_strict
      )
    end)

    it("errors on an unknown --strict category", function()
      local err = args.parse({ "mutation", "--strict=killed", "spec" })

      assert.match("invalid %-%-strict category: killed", err)
    end)

    it("leaves the gate disabled without --strict", function()
      assert.is_nil(args.parse({ "mutation", "spec" }).mutation_strict)
    end)

    it("reads the config file path", function()
      local file = helper.test_data:create_file("mutation.json", "{}")

      local opts = args.parse({ "mutation", "--config=" .. file, "spec" })

      assert.equal(file, opts.mutation_config)
    end)

    it("leaves opts.mutation_config nil without --config", function()
      assert.is_nil(args.parse({ "mutation", "spec" }).mutation_config)
    end)

    it("errors when the --config file does not exist", function()
      local err = args.parse({ "mutation", "--config=/no/such.json", "spec" })

      assert.match("%-%-config file not found", err)
    end)

    it("verifies the baseline entries alongside the scored mutants with --verify-baseline", function()
      local file = helper.test_data:create_file("mutation.json", "{}")

      local opts = args.parse({ "mutation", "--config=" .. file, "--verify-baseline", "spec" })

      assert.is_true(opts.mutation_verify_baseline)
      assert.is_false(opts.mutation_verify_baseline_only)
    end)

    it("leaves the baseline trusted without --verify-baseline", function()
      local opts = args.parse({ "mutation", "spec" })

      assert.is_false(opts.mutation_verify_baseline)
      assert.is_false(opts.mutation_verify_baseline_only)
    end)

    it("errors when --verify-baseline is given without --config", function()
      local err = args.parse({ "mutation", "--verify-baseline", "spec" })

      assert.match("%-%-verify%-baseline requires %-%-config", err)
    end)

    it("gates the scored mutants when --verify-baseline is combined with --strict", function()
      local file = helper.test_data:create_file("mutation.json", "{}")

      local opts = args.parse({ "mutation", "--config=" .. file, "--verify-baseline", "--strict", "spec" })

      assert.is_true(opts.mutation_verify_baseline)
      assert.is_true(opts.mutation_strict.survived)
    end)

    it("leaves every mutant outside the baseline unrun under verify-baseline", function()
      local file = helper.test_data:create_file("mutation.json", "{}")

      local opts = args.parse({ "mutation", "verify-baseline", "--config=" .. file, "spec" })

      assert.is_true(opts.mutation_verify_baseline)
      assert.is_true(opts.mutation_verify_baseline_only)
    end)

    it("errors when verify-baseline has no config to take the entries from", function()
      local err = args.parse({ "mutation", "verify-baseline", "spec" })

      assert.match("verify%-baseline requires %-%-config", err)
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

    it("returns the help flag before reaching the no-paths check", function()
      helper.test_data:cd("")

      local opts = args.parse({ "-h" })

      assert.is_true(opts.help)
    end)
  end)
end)

describe("ntf.core.controller.args.usage", function()
  it("spells the usage line with the command path, bracketing what a default supplies", function()
    assert.match("^Usage: ntf %[run%] %[options%]", args.usage("run"))
    assert.match("^Usage: ntf list %[options%]", args.usage("list"))
    assert.match("^Usage: ntf mutation %[run%] %[options%]", args.usage("mutation.run"))
    assert.match("^Usage: ntf mutation list %[options%]", args.usage("mutation.list"))
  end)

  it("falls back to the default command", function()
    assert.equal(args.usage("run"), args.usage())
  end)

  it("lists the group a command is the fallback of", function()
    local lines = vim.split(args.usage("mutation.run"), "\n", { plain = true })

    assert.is_true(vim.tbl_contains(lines, "Commands:"))
    assert.is_true(vim.tbl_contains(lines, "  list             list the mutants with coverage, without scoring them"))
  end)

  it("describes a command that has to be named instead of listing its group", function()
    local lines = vim.split(args.usage("mutation.list"), "\n", { plain = true })

    assert.is_false(vim.tbl_contains(lines, "Commands:"))
    assert.is_true(vim.tbl_contains(lines, "list the mutants with coverage, without scoring them"))
  end)

  it("aligns the longest label two spaces from its description", function()
    local command = command_of({ "mutation" })
    local longest = command.flags[1]
    for _, flag in ipairs(command.flags) do
      if #args.flag_label(flag) > #args.flag_label(longest) then
        longest = flag
      end
    end

    local lines = vim.split(args.usage(command.id), "\n", { plain = true })

    assert.is_true(vim.tbl_contains(lines, ("  %s  %s"):format(args.flag_label(longest), longest.description)))
  end)

  it("renders every label longer than one character, so the width seed never survives math.max", function()
    local commands = { args.root }
    while #commands > 0 do
      local command = table.remove(commands)
      for _, sub in ipairs(command.subcommands or {}) do
        assert.is_true(#args.command_label(sub, command) > 1)
        table.insert(commands, sub)
      end
      for _, flag in ipairs(command.flags or {}) do
        assert.is_true(#args.flag_label(flag) > 1)
      end
    end
  end)
end)

describe("ntf.core.controller.args.command_label", function()
  it("marks the subcommand a command falls back to", function()
    assert.equal("run (default)", args.command_label(command_of({ "run" }), args.root))
  end)

  it("shows a subcommand that has to be named as its bare name", function()
    assert.equal("list", args.command_label(command_of({ "list" }), args.root))
  end)
end)

describe("ntf.core.controller.args.flag_label", function()
  --- @param argv string[]
  --- @param name string
  --- @return string
  local label = function(argv, name)
    for _, flag in ipairs(command_of(argv).flags) do
      if flag.name == name then
        return args.flag_label(flag)
      end
    end
    error("no such flag: " .. name)
  end

  it("shows a flag taking no value as its bare token", function()
    assert.equal("--verify-baseline", label({ "mutation" }, "--verify-baseline"))
  end)

  it("joins the aliases before the token", function()
    assert.equal("-h, --help", label({}, "--help"))
  end)

  it("appends the placeholder of a required value", function()
    assert.equal("--timeout=MS", label({}, "--timeout"))
  end)

  it("brackets the placeholder of an optional value", function()
    assert.equal("--coverage[=FILE]", label({}, "--coverage"))
  end)
end)
