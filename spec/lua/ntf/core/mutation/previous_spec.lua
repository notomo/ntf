local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local previous = require("ntf.core.mutation.previous")
local helper = require("ntf.test.helper")

local SOURCE = "return true\n"

--- @param row integer
--- @param killed_by string?
--- @param over table? what the record differs in from a one-column swap-relational
--- @return table # one NtfMutationResultRecord
local function record(row, killed_by, over)
  return vim.tbl_extend("force", {
    row = row,
    col = 9,
    end_row = row,
    end_col = 10,
    operator = "swap-relational",
    original = "<",
    replacement = "<=",
    status = killed_by and "killed" or "survived",
    killed_by = killed_by,
  }, over or {})
end

--- @param path string
--- @param row integer
--- @param over table? what the mutant differs in from the record above
--- @return table # one NtfMutant
local function mutant(path, row, over)
  return vim.tbl_extend("force", { path = path }, record(row, nil, over))
end

--- @param file string
--- @param name string full name of the one test the trial runs
--- @return table[] # one NtfMutantTrial over that spec file
local function trials(file, name)
  return { { item = { file = file, node_id = "1.1", names = { name } }, baseline_ms = 0 } }
end

describe("ntf.core.mutation.previous", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  --- @param over table? what the filed results differ in from a killed mutant of an unchanged file
  --- @return table filed, string source, string spec
  local function filed_run(over)
    local source = helper.test_data:create_file("lua/mod.lua", SOURCE)
    local spec = helper.test_data:create_file("mod_spec.lua", SOURCE)
    local digests = {
      [source] = vim.fn.sha256(SOURCE),
      [spec] = vim.fn.sha256(SOURCE),
    }
    return vim.tbl_extend("force", {
      files = { [source] = { record(3, "killed it") } },
      digests = digests,
    }, over or {}),
      source,
      spec
  end

  it("names the test that killed that very mutant, whatever has changed since", function()
    local filed, source = filed_run()
    helper.test_data:create_file("lua/mod.lua", "return false\n")

    local killer = previous.new(filed, true).killer

    assert.equal("killed it", killer(mutant(source, 3)))
    assert.is_nil(killer(mutant(source, 4)))
    assert.is_nil(killer(mutant(source, 3, { col = 10 })))
    assert.is_nil(killer(mutant(source, 3, { operator = "swap-boolean" })))
    assert.is_nil(killer(mutant(source, 3, { replacement = ">=" })))
  end)

  it("closes the file it read a digest from", function()
    local filed, source, spec = filed_run()

    assert.is_false(helper.leaves_file_open(spec, function()
      previous.new(filed, true).settled(mutant(source, 3), trials(spec, "killed it"))
    end))
  end)

  it("names nobody where no run has filed results yet", function()
    assert.is_nil(previous.new(nil, true).killer(mutant("/p/lua/mod.lua", 3)))
  end)

  it("settles a mutant whose file and covering specs are byte for byte what the run before read", function()
    local filed, source, spec = filed_run()

    local settled = previous.new(filed, true).settled(mutant(source, 3), trials(spec, "killed it"))

    assert.equal("killed it", settled)
  end)

  it("settles nothing once the mutated file has changed", function()
    local filed, source, spec = filed_run()
    helper.test_data:create_file("lua/mod.lua", "return false\n")

    local settled = previous.new(filed, true).settled(mutant(source, 3), trials(spec, "killed it"))

    assert.is_nil(settled)
  end)

  it("settles nothing once a spec file covering it has changed", function()
    local filed, source, spec = filed_run()
    helper.test_data:create_file("mod_spec.lua", "return false\n")

    local settled = previous.new(filed, true).settled(mutant(source, 3), trials(spec, "killed it"))

    assert.is_nil(settled)
  end)

  it("settles nothing where the test that killed it is no test of this run", function()
    local filed, source, spec = filed_run()

    local settled = previous.new(filed, true).settled(mutant(source, 3), trials(spec, "another test"))

    assert.is_nil(settled)
  end)

  it("settles nothing for a mutant the run before did not kill", function()
    local filed, source, spec = filed_run({ files = {} })
    filed.files[source] = { record(3, nil) }

    local settled = previous.new(filed, true).settled(mutant(source, 3), trials(spec, "killed it"))

    assert.is_nil(settled)
  end)

  it("settles nothing at all where the run was told to score every mutant again", function()
    local filed, source, spec = filed_run()

    local settled = previous.new(filed, false).settled(mutant(source, 3), trials(spec, "killed it"))

    assert.is_nil(settled)
  end)

  it("files a digest of every file it read, changed or not, for the next run to tell a change by", function()
    local filed, source, spec = filed_run()
    helper.test_data:create_file("lua/mod.lua", "return false\n")
    local other = helper.test_data:create_file("other_spec.lua", SOURCE)

    local read = previous.new(filed, true)
    read.settled(mutant(source, 3), vim.list_extend(trials(spec, "killed it"), trials(other, "another test")))

    local kept = {}
    for path, digest in pairs(read.digests()) do
      kept[path] = digest
    end

    assert.same({
      [source] = vim.fn.sha256("return false\n"),
      [spec] = vim.fn.sha256(SOURCE),
      [other] = vim.fn.sha256(SOURCE),
    }, kept)
  end)

  it("reads a spec file that is gone as one with nothing in it, which settles no mutant", function()
    local filed, source = filed_run()
    local gone = helper.test_data:path("never_written_spec.lua")

    local read = previous.new(filed, true)
    local settled = read.settled(mutant(source, 3), trials(gone, "killed it"))

    assert.is_nil(settled)
    assert.equal(vim.fn.sha256(""), read.digests()[gone])
  end)
end)
