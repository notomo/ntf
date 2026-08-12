local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local schedule = require("ntf.core.controller.schedule")
local helper = require("ntf.test.helper")

--- @param root string
--- @param file string relative spec path
--- @param name string
local function item(root, file, name)
  return { file = vim.fs.joinpath(root, file), node_id = "1.1", names = { "group", name } }
end

--- @param root string
--- @param file string relative spec path
--- @param name string
--- @param duration number? seconds
--- @param status string?
local function result(root, file, name, duration, status)
  return {
    id = "1.1",
    names = { "group", name },
    file = vim.fs.joinpath(root, file),
    status = status or "passed",
    duration = duration,
  }
end

describe("ntf.core.controller.schedule", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("defaults the cache to a file named for the working directory, under the cache directory", function()
    local path = schedule.default_path()

    assert.equal(vim.fs.joinpath(vim.fn.stdpath("cache"), "ntf", "schedule"), vim.fs.dirname(path))
    assert.match("^%%.*%%.*%.json$", vim.fs.basename(path))
  end)

  it("orders the slowest test first", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    schedule.save(path, schedule.load(path), {
      result(root, "spec/a_spec.lua", "fast", 0.01),
      result(root, "spec/a_spec.lua", "slow", 2.0),
      result(root, "spec/b_spec.lua", "medium", 0.5),
    }, root)

    local ordered = schedule.order({
      item(root, "spec/a_spec.lua", "fast"),
      item(root, "spec/a_spec.lua", "slow"),
      item(root, "spec/b_spec.lua", "medium"),
    }, schedule.load(path), root)

    assert.same({ "slow", "medium", "fast" }, {
      ordered[1].names[2],
      ordered[2].names[2],
      ordered[3].names[2],
    })
  end)

  it("orders by a cache key it normalizes, so an odd spelling of a path still finds its entry", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    schedule.save(path, schedule.load(path), {
      result(root, "spec/a_spec.lua", "fast", 0.01),
      result(root, "spec/a_spec.lua", "slow", 2.0),
    }, root)

    local ordered = schedule.order({
      item(root, "spec/./a_spec.lua", "fast"),
      item(root, "spec/./a_spec.lua", "slow"),
    }, schedule.load(path), root .. "/")

    assert.same({ "slow", "fast" }, { ordered[1].names[2], ordered[2].names[2] })
  end)

  it("saves under a cache key it normalizes, so an odd spelling of the working directory still keys it", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")

    schedule.save(path, schedule.load(path), { result(root, "spec/./a_spec.lua", "one", 0.25) }, root .. "/")

    assert.equal(250, schedule.load(path).files["spec/a_spec.lua"]["group one"].ms)
  end)

  it("treats a test the cache does not know as the slowest", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "known", 2.0) }, root)

    local ordered = schedule.order({
      item(root, "spec/a_spec.lua", "known"),
      item(root, "spec/a_spec.lua", "unknown"),
    }, schedule.load(path), root)

    assert.equal("unknown", ordered[1].names[2])
  end)

  it("keeps the given order between tests with the same duration, however the sort shuffles a tie", function()
    local root = helper.test_data.full_path
    local items = {
      item(root, "spec/a_spec.lua", "one"),
      item(root, "spec/a_spec.lua", "two"),
      item(root, "spec/a_spec.lua", "three"),
      item(root, "spec/a_spec.lua", "four"),
    }

    local ordered = schedule.order(items, schedule.load(helper.test_data:path("nope.json")), root)

    assert.same({ "one", "two", "three", "four" }, {
      ordered[1].names[2],
      ordered[2].names[2],
      ordered[3].names[2],
      ordered[4].names[2],
    })
  end)

  it("keys a spec outside the working directory by its full path", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    local outside = "/elsewhere/x_spec.lua"

    schedule.save(path, schedule.load(path), {
      { id = "1.1", names = { "group", "one" }, file = outside, status = "passed", duration = 1.0 },
    }, root)

    assert.equal(1000, schedule.load(path).files[outside]["group one"].ms)
  end)

  it("saves durations keyed by relative path and full name", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")

    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "one", 0.25, "failed") }, root)

    local entry = schedule.load(path).files["spec/a_spec.lua"]["group one"]
    assert.equal(250, entry.ms)
    assert.equal("failed", entry.status)
  end)

  it("creates the directory the cache file goes in, which nothing else makes", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("cache/ntf/schedule.json")

    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "one", 0.25) }, root)

    assert.equal(250, schedule.load(path).files["spec/a_spec.lua"]["group one"].ms)
  end)

  it("closes the cache file it read", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "one", 0.25) }, root)

    assert.is_false(helper.leaves_file_open(path, function()
      schedule.load(path)
    end))
  end)

  it("merges into the existing cache instead of replacing it", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    schedule.save(path, schedule.load(path), {
      result(root, "spec/a_spec.lua", "kept", 1.0),
      result(root, "spec/a_spec.lua", "updated", 1.0),
    }, root)

    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "updated", 2.0) }, root)

    local by_name = schedule.load(path).files["spec/a_spec.lua"]
    assert.equal(1000, by_name["group kept"].ms)
    assert.equal(2000, by_name["group updated"].ms)
  end)

  it("keeps the old duration for a result without one", function()
    local root = helper.test_data.full_path
    local path = helper.test_data:path("schedule.json")
    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "one", 1.0) }, root)

    schedule.save(path, schedule.load(path), { result(root, "spec/a_spec.lua", "one", nil, "pending") }, root)

    assert.equal(1000, schedule.load(path).files["spec/a_spec.lua"]["group one"].ms)
  end)

  it("loads a version 1 cache file", function()
    local path = helper.test_data:create_file(
      "v1.json",
      '{"version":1,"files":{"spec/a_spec.lua":{"group one":{"ms":250,"status":"passed"}}}}'
    )

    assert.equal(250, schedule.load(path).files["spec/a_spec.lua"]["group one"].ms)
  end)

  it("loads a missing, corrupt or incompatible file as an empty cache", function()
    local corrupt = helper.test_data:create_file("corrupt.json", "{ not json")
    local scalar = helper.test_data:create_file("scalar.json", "5")
    local incompatible = helper.test_data:create_file(
      "incompatible.json",
      '{"version":999,"files":{"spec/a_spec.lua":{"group one":{"ms":250,"status":"passed"}}}}'
    )
    local no_files = helper.test_data:create_file("no_files.json", '{"version":1,"files":"nope"}')

    assert.same({}, schedule.load(helper.test_data:path("nope.json")).files)
    assert.same({}, schedule.load(corrupt).files)
    assert.same({}, schedule.load(scalar).files)
    assert.same({}, schedule.load(incompatible).files)
    assert.same({}, schedule.load(no_files).files)
  end)

  it("ignores an unwritable path instead of failing the run", function()
    local root = helper.test_data.full_path
    local blocker = helper.test_data:create_file("blocker", "")

    schedule.save(
      vim.fs.joinpath(blocker, "sub", "schedule.json"),
      schedule.load(helper.test_data:path("nope.json")),
      { result(root, "spec/a_spec.lua", "one", 1.0) },
      root
    )
  end)
end)
