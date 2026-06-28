local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local collector = require("ntf.core.coverage.collector")
local helper = require("ntf.test.helper")

describe("ntf.core.coverage.collector.merge", function()
  it("sums per-line hits across workers and tracks the max line", function()
    local into = {}
    collector.merge(into, { ["/a.lua"] = { max = 4, lines = { ["2"] = 1, ["4"] = 3 } } })
    collector.merge(into, { ["/a.lua"] = { max = 7, lines = { ["2"] = 5, ["7"] = 1 } } })

    assert.same({ ["/a.lua"] = { max = 7, lines = { [2] = 6, [4] = 3, [7] = 1 } } }, into)
  end)

  it("tolerates a nil part (a worker that reported no coverage)", function()
    local into = {}
    collector.merge(into, nil)

    assert.same({}, into)
  end)
end)

describe("ntf.core.coverage.collector.start/stop", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("counts executed lines of a measured file under cwd", function()
    -- A non-spec file under the data dir: it is under cwd (so measured) and does
    -- not match *_spec.lua (so not excluded).
    local file = helper.test_data:create_file(
      "subject.lua",
      table.concat({
        "local function add(a, b)",
        "  local r = a + b",
        "  return r",
        "end",
        "return add",
      }, "\n")
    )
    local add = assert(loadfile(file))()

    collector.start({ cwd = helper.test_data.full_path })
    add(1, 2)
    add(3, 4)
    local data = collector.stop()

    local key = vim.fs.normalize(file)
    assert.truthy(data[key])
    -- The function body (lines 2 and 3) ran twice; the chunk's top lines ran
    -- before start, so they are not counted.
    assert.equal(2, data[key].lines["2"])
    assert.equal(2, data[key].lines["3"])
  end)

  it("does not measure files outside cwd", function()
    collector.start({ cwd = helper.test_data.full_path })
    -- ntf's own modules live outside the data dir, so running one is not counted.
    require("ntf.core.coverage.report")
    local data = collector.stop()

    assert.same({}, data)
  end)

  it("does not measure files under an excluded test directory", function()
    -- The test tree (specs and any deps alongside them) is excluded. The dir need
    -- not be `spec/`: here it is `test/`, derived from where the spec lives.
    local file = helper.test_data:create_file(
      "test/sub.lua",
      table.concat({
        "local function add(a, b)",
        "  return a + b",
        "end",
        "return add",
      }, "\n")
    )
    local add = assert(loadfile(file))()
    local excludes = collector.exclude_roots({ helper.test_data:path("test/x_spec.lua") }, helper.test_data.full_path)

    collector.start({ cwd = helper.test_data.full_path, excludes = excludes })
    add(1, 2)
    local data = collector.stop()

    assert.same({}, data)
  end)
end)

describe("ntf.core.coverage.collector.exclude_roots", function()
  -- Build the fake paths under a real absolute base so the test holds on Windows
  -- too, where a bare "/repo" would gain a drive letter once made absolute.
  local function abs(path)
    return (vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", ""))
  end
  local repo = abs("/repo")

  it("derives each spec file's top-level directory under cwd", function()
    local roots = collector.exclude_roots({ repo .. "/spec/lua/x/a_spec.lua" }, repo)

    assert.same({ repo .. "/spec/" }, roots)
  end)

  it("dedups roots shared by many spec files", function()
    local roots = collector.exclude_roots({ repo .. "/spec/a_spec.lua", repo .. "/spec/lua/b_spec.lua" }, repo)

    assert.same({ repo .. "/spec/" }, roots)
  end)

  it("ignores spec files outside cwd and those sitting directly in cwd", function()
    local roots = collector.exclude_roots({ abs("/elsewhere") .. "/a_spec.lua", repo .. "/top_spec.lua" }, repo)

    assert.same({}, roots)
  end)
end)
