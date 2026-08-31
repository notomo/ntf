local ntf = require("ntf")
local describe, before_each, after_each, it, pending, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.pending, ntf.finally, ntf.assert
local collector = require("ntf.core.coverage.collector")
local normalize = require("ntf.core.path").normalize
local helper = require("ntf.test.helper")

local LOOP_BODY_LINE = "4"

--- @param name string file name under the test data dir
--- @return string # the normalized path of a file returning a function whose loop the JIT compiles once it is called with enough iterations
local function loop_file(name)
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
  return vim.fs.normalize(path)
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

describe("ntf.core.coverage.collector.start/stop", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  local ADD = table.concat({
    "local function add(a, b)",
    "  local r = a + b",
    "  return r",
    "end",
    "return add",
  }, "\n")

  it("counts each statement a dofile'd file runs, the rows it is loaded by among them", function()
    local measured = helper.test_data:create_file("subject.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    local add = dofile(measured)
    add(1, 2)
    add(3, 4)
    local data = collector.stop()

    assert.same({ ["1"] = 1, ["2"] = 2, ["3"] = 2, ["5"] = 1 }, data[vim.fs.normalize(measured)].lines)
  end)

  it("reports the last row it counted as the max", function()
    local measured = helper.test_data:create_file("subject.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    dofile(measured)
    local data = collector.stop()

    assert.equal(5, data[vim.fs.normalize(measured)].max)
  end)

  it("keys the counted rows by string, since vim.json.encode rejects the sparse array they would form", function()
    local measured = helper.test_data:create_file("subject.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    dofile(measured)
    local data = collector.stop()

    assert.same(data, vim.json.decode(vim.json.encode(data)))
  end)

  it("keys every counted row by a string tonumber parses, which its readers rely on", function()
    local measured = helper.test_data:create_file("subject.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    dofile(measured)
    local data = collector.stop()

    local parsed = {}
    for row in pairs(data[vim.fs.normalize(measured)].lines) do
      table.insert(parsed, tonumber(row))
    end
    table.sort(parsed)
    assert.same({ 1, 5 }, parsed)
  end)

  it("counts a file loaded through loadfile", function()
    local measured = helper.test_data:create_file("subject.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    assert(loadfile(measured))()(1, 2)
    local data = collector.stop()

    assert.equal(1, data[vim.fs.normalize(measured)].lines["2"])
  end)

  it("counts a module the run requires, which Neovim loads through the loadfile it takes the place of", function()
    helper.test_data:create_file("lua/subject.lua", ADD)
    vim.opt.runtimepath:prepend(helper.test_data.full_path)
    finally(function()
      vim.opt.runtimepath:remove(helper.test_data.full_path)
      package.loaded["subject"] = nil
    end)
    require("subject")

    collector.start({ cwd = helper.test_data.full_path })
    require("subject")(1, 2)
    local data = collector.stop()

    local module = vim.fs.normalize(helper.test_data:path("lua/subject.lua"))
    assert.equal(1, data[module].lines["1"])
    assert.equal(1, data[module].lines["2"])
  end)

  it("counts every iteration of a loop hot enough for the JIT to compile it", function()
    local measured = loop_file("loop.lua")

    collector.start({ cwd = helper.test_data.full_path })
    dofile(measured)(HOT_ENOUGH_TO_COMPILE)
    local data = collector.stop()

    assert.equal(HOT_ENOUGH_TO_COMPILE, data[measured].lines[LOOP_BODY_LINE])
  end)

  it("leaves a file it cannot instrument loadable, counting none of it", function()
    local shebang_is_no_lua_expression = "#!/usr/bin/env lua\nreturn 1"
    local measured = helper.test_data:create_file("subject.lua", shebang_is_no_lua_expression)

    collector.start({ cwd = helper.test_data.full_path })
    local loaded = dofile(measured)
    local data = collector.stop()

    assert.equal(1, loaded)
    assert.same({}, data)
  end)

  it("puts back the loaders it took the place of", function()
    local outer_loadfile, outer_dofile = loadfile, dofile
    local outer_loaders = vim.list_extend({}, package.loaders)

    collector.start({ cwd = helper.test_data.full_path })
    collector.stop()

    assert.equal(outer_loadfile, loadfile)
    assert.equal(outer_dofile, dofile)
    assert.same(outer_loaders, package.loaders)
  end)

  it("counts a module Lua itself finds beside the working directory, which no loadfile of ours is asked for", function()
    helper.test_data:create_file("subject.lua", ADD)
    local cwd = vim.fn.getcwd()
    vim.fn.chdir(helper.test_data.full_path)
    finally(function()
      vim.fn.chdir(cwd)
      package.loaded["subject"] = nil
    end)

    collector.start({ cwd = helper.test_data.full_path })
    require("subject")(1, 2)
    local data = collector.stop()

    local module = vim.fs.normalize(helper.test_data:path("subject.lua"))
    assert.equal(1, data[module].lines["2"])
  end)

  it("leaves a module the runtimepath holds to the loader Neovim answers it with", function()
    helper.test_data:create_file("lua/subject.lua", "return 'runtimepath'")
    helper.test_data:create_file("subject.lua", "return 'package.path'")
    vim.opt.runtimepath:prepend(helper.test_data.full_path)
    local cwd = vim.fn.getcwd()
    vim.fn.chdir(helper.test_data.full_path)
    finally(function()
      vim.fn.chdir(cwd)
      vim.opt.runtimepath:remove(helper.test_data.full_path)
      package.loaded["subject"] = nil
    end)

    collector.start({ cwd = helper.test_data.full_path })
    local loaded = require("subject")
    collector.stop()

    assert.equal("runtimepath", loaded)
  end)

  it("leaves a module the runtimepath holds as a directory to the loader Neovim answers it with", function()
    helper.test_data:create_file("lua/subject/init.lua", "return 'runtimepath'")
    helper.test_data:create_file("subject.lua", "return 'package.path'")
    vim.opt.runtimepath:prepend(helper.test_data.full_path)
    local cwd = vim.fn.getcwd()
    vim.fn.chdir(helper.test_data.full_path)
    finally(function()
      vim.fn.chdir(cwd)
      vim.opt.runtimepath:remove(helper.test_data.full_path)
      package.loaded["subject"] = nil
    end)

    collector.start({ cwd = helper.test_data.full_path })
    local loaded = require("subject")
    collector.stop()

    assert.equal("runtimepath", loaded)
  end)

  it("leaves a file it has stopped measuring uncounted", function()
    local measured = helper.test_data:create_file("subject.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    local data = collector.stop()
    dofile(measured)

    assert.same({}, data)
  end)

  it("does not measure files outside cwd", function()
    local module_outside_cwd = "ntf.core.coverage.report"
    package.loaded[module_outside_cwd] = nil

    collector.start({ cwd = helper.test_data.full_path })
    require(module_outside_cwd)
    local data = collector.stop()

    assert.same({}, data)
  end)

  it("does not measure a file sitting alongside the specs, in a test tree left out of the run", function()
    local file = helper.test_data:create_file("test/sub.lua", ADD)
    local excludes = collector.exclude_paths({ helper.test_data:path("test") })

    collector.start({ cwd = helper.test_data.full_path, excludes = excludes })
    dofile(file)(1, 2)
    local data = collector.stop()

    assert.same({}, data)
  end)

  it("does not measure a spec file", function()
    local file = helper.test_data:create_file("mod_spec.lua", ADD)

    collector.start({ cwd = helper.test_data.full_path })
    dofile(file)(1, 2)
    local data = collector.stop()

    assert.same({}, data)
  end)

  it("leaves a module no loader finds to the error the require raises", function()
    collector.start({ cwd = helper.test_data.full_path })
    local ok, err = pcall(require, "no.such.module")
    collector.stop()

    assert.is_false(ok)
    assert.match("module 'no.such.module' not found", err)
  end)

  it("leaves a module outside cwd loaded, so that whoever holds it keeps the copy it holds", function()
    local module_outside_cwd = "ntf.core.coverage.report"
    local held = require(module_outside_cwd)

    collector.start({ cwd = helper.test_data.full_path })
    local required = require(module_outside_cwd)
    collector.stop()

    assert.equal(held, required)
  end)

  it("hands a file it cannot read back to the loader it took the place of", function()
    collector.start({ cwd = helper.test_data.full_path })
    local ok, err = loadfile(helper.test_data:path("missing.lua"))
    collector.stop()

    assert.is_nil(ok)
    assert.equal("string", type(err))
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
