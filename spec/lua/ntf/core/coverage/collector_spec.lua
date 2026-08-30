local ntf = require("ntf")
local describe, before_each, after_each, it, pending, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.pending, ntf.finally, ntf.assert
local collector = require("ntf.core.coverage.collector")
local normalize = require("ntf.core.path").normalize
local helper = require("ntf.test.helper")

--- @return fun() # puts the debug hook installed now back, which the end of the test does too
local function keep_debug_hook()
  local hook, mask, count = debug.gethook()
  local restore = function()
    debug.sethook(hook, mask, count)
  end
  finally(restore)
  return restore
end

local LOOP_BODY_LINE = "4"

--- @param name string file name under the test data dir
--- @return fun(n: integer) # a function whose loop the JIT compiles once it is called with enough iterations
--- @return string # the normalized path it was loaded from
local function loop_function(name)
  local path = helper.test_data:create_file(
    name,
    table.concat({
      "local function total(n)",
      "  local sum = 0",
      "  for i = 1, n do",
      "    sum = sum + i",
      "  end",
      "  return sum",
      "end",
      "return total",
    }, "\n")
  )
  return assert(loadfile(path))(), vim.fs.normalize(path)
end

local HOT_ENOUGH_TO_COMPILE = 1000

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

  it(
    "counts the hooked function's lines under its source path, called directly since debug.sethook hooks do not nest",
    function()
      local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })
      local path = vim.fs.normalize(helper.test_data:path("covered.lua"))

      run_hook(hook, "@" .. path, { 3, 3, 7, 1 })

      assert.same({ [path] = { max = 7, lines = { ["1"] = 1, ["3"] = 2, ["7"] = 1 } } }, data)
    end
  )

  it("records an oddly spelled source under its normalized path, so one file never gets two keys", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })
    local path = vim.fs.normalize(helper.test_data:path("covered.lua"))

    run_hook(hook, "@" .. helper.test_data.full_path .. "/./covered.lua", { 1 })

    assert.same({ path }, vim.tbl_keys(data))
  end)

  it("keys the recorded lines by string, since vim.json.encode rejects the sparse array they would form", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })

    run_hook(hook, "@" .. helper.test_data:path("covered.lua"), { 3, 7 })

    assert.same(data, vim.json.decode(vim.json.encode(data)))
  end)

  it("keys every recorded line by a string tonumber parses, which its readers rely on", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })
    local path = vim.fs.normalize(helper.test_data:path("covered.lua"))

    run_hook(hook, "@" .. path, { 3, 7 })

    local parsed = {}
    for line in pairs(data[path].lines) do
      table.insert(parsed, tonumber(line))
    end
    table.sort(parsed)
    assert.same({ 3, 7 }, parsed)
  end)

  it("reports max as a number of at least one, recording a line before it ever creates the entry", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })
    local path = vim.fs.normalize(helper.test_data:path("covered.lua"))

    run_hook(hook, "@" .. path, { 1 })

    assert.equal("number", type(data[path].max))
    assert.is_true(data[path].max >= 1)
  end)

  it("ignores line numbers below one", function()
    local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })

    run_hook(hook, "@" .. helper.test_data:path("covered.lua"), { 0 })

    assert.same({}, data)
  end)

  it("records nothing for a relative source, as a neovim builtin module's `@vim/fs` is", function()
    local cwd = vim.fn.getcwd()
    local hook, data = collector.line_hook({ cwd = cwd })

    run_hook(hook, "@vim/fs", { 3 })

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

  it(
    "counts every iteration of a loop hot enough to compile, since a line hook stops the JIT recording traces",
    function()
      local total, measured = loop_function("loop.lua")
      keep_debug_hook()
      local hook, data = collector.line_hook({ cwd = helper.test_data.full_path })
      require("jit").on()

      debug.sethook(hook, "l")
      total(HOT_ENOUGH_TO_COMPILE)
      debug.sethook()

      assert.equal(HOT_ENOUGH_TO_COMPILE, data[measured].lines[LOOP_BODY_LINE])
    end
  )
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

  it("puts back the debug hook that was installed before it started", function()
    local outer_hook = function() end
    keep_debug_hook()
    debug.sethook(outer_hook, "l")

    collector.start({ cwd = helper.test_data.full_path })
    collector.stop()

    assert.equal(outer_hook, debug.gethook())
  end)

  it("reports partial counts and leaves the replacement alone when something takes the hook slot over", function()
    keep_debug_hook()
    local replacement = function() end

    collector.start({ cwd = helper.test_data.full_path })
    debug.sethook(replacement, "l")
    local _, problem = collector.stop()

    assert.equal(replacement, debug.gethook())
    assert.match("was replaced while the test ran", problem)
  end)

  it("counts the lines of a function the JIT had already compiled before it started", function()
    local total, measured = loop_function("hot.lua")
    local restore_hook = keep_debug_hook()
    debug.sethook()
    require("jit").on()
    total(HOT_ENOUGH_TO_COMPILE)
    restore_hook()

    collector.start({ cwd = helper.test_data.full_path })
    total(1)
    local data = collector.stop()

    assert.equal(1, data[measured].lines[LOOP_BODY_LINE])
  end)

  it("does not measure files outside cwd", function()
    local module_outside_cwd = "ntf.core.coverage.report"

    collector.start({ cwd = helper.test_data.full_path })
    require(module_outside_cwd)
    local data = collector.stop()

    assert.same({}, data)
  end)

  it("does not measure a file sitting alongside the specs, in a test tree left out of the run", function()
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
    local excludes = collector.exclude_paths({ helper.test_data:path("test") })

    collector.start({ cwd = helper.test_data.full_path, excludes = excludes })
    add(1, 2)
    local data = collector.stop()

    assert.same({}, data)
  end)
end)

describe("ntf.core.coverage.collector.release", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("says the counts are partial when its hook is no longer the one in place", function()
    local problem = collector.release({ hook = function() end, data = {}, previous = { mask = "", count = 0 } })

    assert.match("was replaced while the test ran", problem)
  end)

  it("puts the previous hook back when its own hook is still in place", function()
    keep_debug_hook()
    local installed = function() end
    local previous = function() end
    debug.sethook(installed, "l")

    local problem =
      collector.release({ hook = installed, data = {}, previous = { hook = previous, mask = "l", count = 0 } })

    assert.is_nil(problem)
    assert.equal(previous, debug.gethook())
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

  it("skips spec files and an excluded test tree", function()
    helper.test_data:create_file("lua/mod_spec.lua", "return 1")
    helper.test_data:create_file("test/x_spec.lua", "return 1")
    helper.test_data:create_file("test/dep.lua", "return 1")
    local excludes = collector.exclude_paths({ helper.test_data:path("test") })

    local files = collector.measurable_files(helper.test_data.full_path, excludes)

    assert.same({}, files)
  end)

  it("lists the same files for an odd spelling of the working directory", function()
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")

    local files = collector.measurable_files(helper.test_data.full_path .. "/./", {})

    assert.same({ vim.fs.normalize(file) }, files)
  end)

  it("lists the files under a working directory named after an environment variable, not the ones it names", function()
    vim.env.NTF_TEST_DIR = "expanded"
    finally(function()
      vim.env.NTF_TEST_DIR = nil
    end)
    local file = helper.test_data:create_file("$NTF_TEST_DIR/lua/mod.lua", "return 1")
    helper.test_data:create_file("expanded/lua/other.lua", "return 1")

    local files = collector.measurable_files(helper.test_data:path("$NTF_TEST_DIR"), {})

    assert.same({ normalize(file) }, files)
  end)

  it("lists a symlinked lua file under the path the link is at, which is what a chunk names", function()
    if vim.fn.has("win32") == 1 then
      return pending("a symlink needs a privileged account on windows")
    end
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    local link = helper.test_data:path("lua/link.lua")
    local ok, err = vim.uv.fs_symlink(file, link)
    if not ok then
      error(err)
    end

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ normalize(link), normalize(file) }, files)
  end)

  it("does not list a symlink pointing at nothing", function()
    if vim.fn.has("win32") == 1 then
      return pending("a symlink needs a privileged account on windows")
    end
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    local ok, err = vim.uv.fs_symlink(helper.test_data:path("lua/gone.lua"), helper.test_data:path("lua/link.lua"))
    if not ok then
      error(err)
    end

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ normalize(file) }, files)
  end)

  it("does not list a symlinked directory as a file of its own", function()
    if vim.fn.has("win32") == 1 then
      return pending("a symlink needs a privileged account on windows")
    end
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    local ok, err = vim.uv.fs_symlink(helper.test_data:path("lua"), helper.test_data:path("linked.lua"))
    if not ok then
      error(err)
    end

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ normalize(file) }, files)
  end)

  it("lists the files sorted, not in the order the walk reaches them", function()
    local nested = helper.test_data:create_file("lua/mod/sub.lua", "return 1")
    local top = helper.test_data:create_file("lua/mod.lua", "return 1")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ normalize(top), normalize(nested) }, files)
  end)

  it("lists only lua files", function()
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    helper.test_data:create_file("lua/notes.txt", "just text")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ vim.fs.normalize(file) }, files)
  end)

  it("does not descend into a dot-prefixed directory, which spec discovery skips too", function()
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    helper.test_data:create_file(".venv/vendored.lua", "return 1")
    helper.test_data:create_file("lua/.cache/generated.lua", "return 1")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ vim.fs.normalize(file) }, files)
  end)

  it("does not list a dot-prefixed lua file", function()
    local file = helper.test_data:create_file("lua/mod.lua", "return 1")
    helper.test_data:create_file("lua/.hidden.lua", "return 1")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({ vim.fs.normalize(file) }, files)
  end)

  it("skips LuaCATS meta files", function()
    helper.test_data:create_file("lua/meta.lua", "--- @meta\nlocal M = {}\nreturn M")

    local files = collector.measurable_files(helper.test_data.full_path, {})

    assert.same({}, files)
  end)

  it("closes the file it read the first line of", function()
    local path = vim.fs.normalize(helper.test_data:create_file("lua/mod.lua", "return 1"))

    assert.is_false(helper.leaves_file_open(path, function()
      collector.is_meta_file(path)
    end))
  end)

  it("treats a file it cannot read as non-meta, called directly since chmod 0 still allows reads on Windows", function()
    local missing = helper.test_data:path("lua/missing.lua")

    assert.is_false(collector.is_meta_file(vim.fs.normalize(missing)))
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
