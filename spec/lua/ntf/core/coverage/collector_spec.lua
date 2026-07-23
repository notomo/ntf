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

describe("ntf.core.coverage.collector.line_hook", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  --- @param hook fun(event:string, line:integer)
  --- @param chunkname string name of the chunk that calls the hook, so it attributes the lines there instead of to this spec file
  --- @param lines integer[] line numbers fed to the hook
  local function run_hook(hook, chunkname, lines)
    local fn = assert(
      loadstring("local hook, lines = ...\nfor _, line in ipairs(lines) do\n  hook('line', line)\nend", chunkname)
    )
    fn(hook, lines)
  end

  it("counts the hooked function's lines under its source path", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })
    local path = vim.fs.normalize(helper.test_data:path("covered.lua"))

    run_hook(hook, "@" .. path, { 3, 3, 7, 1 })

    assert.same({ [path] = { max = 7, lines = { ["1"] = 1, ["3"] = 2, ["7"] = 1 } } }, data)
  end)

  it("ignores line numbers below one", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })

    run_hook(hook, "@" .. helper.test_data:path("covered.lua"), { 0 })

    assert.same({}, data)
  end)

  it("records nothing for non-file chunks, spec files, excluded and outside paths", function()
    local hook, data = collector.line_hook({
      cwd = helper.test_data.full_path,
      excludes = { vim.fs.normalize(helper.test_data:path("excluded")) .. "/" },
    })

    run_hook(hook, "stringchunk", { 3 })
    run_hook(hook, "@" .. helper.test_data:path("excluded/mod.lua"), { 3 })
    run_hook(hook, "@" .. helper.test_data:path("mod_spec.lua"), { 3 })
    run_hook(hook, "@" .. vim.fs.joinpath(vim.fs.normalize(helper.root), "outside.lua"), { 3 })

    assert.same({}, data)
  end)
end)

describe("ntf.core.coverage.collector.start/stop", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("counts executed lines of a measured file under cwd", function()
    local measured = helper.test_data:create_file(
      "subject.lua",
      table.concat({
        "local function add(a, b)",
        "  local r = a + b",
        "  return r",
        "end",
        "return add",
      }, "\n")
    )
    local add = assert(loadfile(measured))()

    collector.start({ cwd = helper.test_data.full_path })
    add(1, 2)
    add(3, 4)
    local data = collector.stop()

    local body_line_hits = { ["2"] = 2, ["3"] = 2 }
    assert.same(body_line_hits, data[vim.fs.normalize(measured)].lines)
  end)

  it("does not measure files outside cwd", function()
    local module_outside_cwd = "ntf.core.coverage.report"

    collector.start({ cwd = helper.test_data.full_path })
    require(module_outside_cwd)
    local data = collector.stop()

    assert.same({}, data)
  end)

  it("does not measure files sitting alongside a spec, whatever the directory is named", function()
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

describe("ntf.core.coverage.collector.measurable_files", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("lists production lua files even if nothing executed them", function()
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ vim.fs.normalize(file) }, files)
  end)

  it("skips spec files and excluded test directories", function()
    helper.test_data:create_file("lua/mod_spec.lua", "return 1")
    local spec_file = helper.test_data:create_file("test/x_spec.lua", "return 1")
    helper.test_data:create_file("test/dep.lua", "return 1")
    local excludes = collector.exclude_roots({ spec_file }, helper.test_data.full_path)

    local files = collector.measurable_files(helper.test_data.full_path, excludes)

    assert.same({}, files)
  end)

  it("lists only lua files", function()
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    helper.test_data:create_file("lua/notes.txt", "just text")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ vim.fs.normalize(file) }, files)
  end)

  it("skips LuaCATS meta files", function()
    helper.test_data:create_file("lua/meta.lua", "--- @meta\nlocal M = {}\nreturn M")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({}, files)
  end)

  it("treats a file it cannot read as non-meta", function()
    local missing = helper.test_data:path("lua/missing.lua")

    assert.is_false(collector.is_meta_file(vim.fs.normalize(missing)))
  end)
end)

describe("ntf.core.coverage.collector.exclude_roots", function()
  --- @param path string
  --- @return string absolute path under a real base, so a bare "/repo" keeps the drive letter it gains on Windows
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

describe("ntf.core.coverage.collector.exclude_paths", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("keeps a directory's trailing slash, so a sibling with the same prefix is not excluded", function()
    local dir = helper.test_data:create_dir("lua/vendor")
    helper.test_data:create_file("lua/vendored.lua", "return 1")

    local prefixes = collector.exclude_paths({ dir })

    assert.same({ vim.fs.normalize(dir) .. "/" }, prefixes)

    local files = collector.measurable_files(helper.test_data.full_path, prefixes)
    assert.same({ vim.fs.normalize(helper.test_data:path("lua/vendored.lua")) }, files)
  end)

  it("excludes a single file", function()
    local file = helper.test_data:create_file("lua/skipped.lua", "return 1")
    helper.test_data:create_file("lua/kept.lua", "return 1")

    local prefixes = collector.exclude_paths({ file })

    local files = collector.measurable_files(helper.test_data.full_path, prefixes)
    assert.same({ vim.fs.normalize(helper.test_data:path("lua/kept.lua")) }, files)
  end)
end)
