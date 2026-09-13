local ntf = require("ntf")
local describe, before_each, after_each, it, finally, assert =
  ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.finally, ntf.assert
local loaded = require("ntf.core.coverage.loaded")
local collector = require("ntf.core.coverage.collector")
local normalize = require("ntf.core.path").normalize
local helper = require("ntf.test.helper")

local MODULE = "return {}"

--- @param name string a module name to require anew at the end of the test
local function unload_after(name)
  finally(function()
    package.loaded[name] = nil
  end)
end

--- @return NtfLoadedFiles # a recording over the test data directory, stopped at the end of the test
local function recording()
  local files = loaded.start(helper.test_data.full_path)
  finally(files.stop)
  return files
end

local function work_in_test_data()
  local cwd = vim.fn.getcwd()
  vim.fn.chdir(helper.test_data.full_path)
  finally(function()
    vim.fn.chdir(cwd)
  end)
end

describe("ntf.core.coverage.loaded.runtime_file", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("names the file Neovim's loader reads a module from, a directory module's init.lua included", function()
    local file = helper.test_data:create_file("lua/ntf_loaded_file.lua", MODULE)
    local init = helper.test_data:create_file("lua/ntf_loaded_dir/init.lua", MODULE)
    vim.opt.runtimepath:prepend(helper.test_data.full_path)
    finally(function()
      vim.opt.runtimepath:remove(helper.test_data.full_path)
    end)

    assert.equal(normalize(file), normalize(assert(loaded.runtime_file("ntf_loaded_file"))))
    assert.equal(normalize(init), normalize(assert(loaded.runtime_file("ntf_loaded_dir"))))
  end)

  it("names nothing for a module in no lua/ directory of the runtimepath", function()
    assert.is_nil(loaded.runtime_file("ntf_loaded_nowhere"))
  end)
end)

describe("ntf.core.coverage.loaded.start", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("records a module Neovim's loader reads from the project", function()
    local file = helper.test_data:create_file("lua/ntf_loaded_subject.lua", MODULE)
    vim.opt.runtimepath:prepend(helper.test_data.full_path)
    finally(function()
      vim.opt.runtimepath:remove(helper.test_data.full_path)
    end)
    unload_after("ntf_loaded_subject")

    local files = recording()
    require("ntf_loaded_subject")

    assert.same({ normalize(file) }, files.paths())
  end)

  it(
    "records a module Lua itself finds beside the working directory, which no loadfile of ours is asked for",
    function()
      local file = helper.test_data:create_file("ntf_loaded_subject.lua", MODULE)
      work_in_test_data()
      unload_after("ntf_loaded_subject")

      local files = recording()
      require("ntf_loaded_subject")

      assert.same({ normalize(file) }, files.paths())
    end
  )

  it("records the files loadfile and dofile read, handing back what each does", function()
    local read = helper.test_data:create_file("read.lua", "return 'read'")
    local ran = helper.test_data:create_file("ran.lua", "return 'ran'")

    local files = recording()
    local chunk = assert(loadfile(read))
    local result = dofile(ran)

    assert.equal("read", chunk())
    assert.equal("ran", result)
    assert.same({ normalize(ran), normalize(read) }, files.paths())
  end)

  it("records a module the coverage measurement loads itself, whose loader answers before any after it", function()
    helper.test_data:create_file("subject.lua", MODULE)
    work_in_test_data()
    unload_after("subject")

    local files = recording()
    collector.start({ cwd = helper.test_data.full_path })
    require("subject")
    collector.stop()

    assert.same({ normalize(helper.test_data:path("subject.lua")) }, files.paths())
  end)

  it("leaves a module found nowhere to the error require raises for it, recording nothing", function()
    work_in_test_data()
    local files = recording()

    local ok, err = pcall(require, "ntf_loaded_nowhere")

    assert.is_false(ok)
    assert.match("module 'ntf_loaded_nowhere' not found", err)
    assert.same({}, files.paths())
  end)

  it("leaves a load from stdin, which names no file, to run as it does, recording nothing", function()
    work_in_test_data()
    local files = recording()

    local chunk = loadfile()
    local ran = pcall(dofile)

    assert.is_true(chunk ~= nil or ran)
    assert.same({}, files.paths())
  end)

  it("records a file loadfile reaches for and finds missing, whose arrival changes what the load does", function()
    local missing = helper.test_data:path("missing.lua")

    local files = recording()
    local _ = loadfile(missing)

    assert.same({ normalize(missing) }, files.paths())
  end)

  it("leaves out a file outside the project", function()
    local outside = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ MODULE }, outside)
    finally(function()
      vim.fn.delete(outside)
    end)

    local files = recording()
    dofile(outside)

    assert.same({}, files.paths())
  end)

  it("records a file once, however often it is read", function()
    local read = helper.test_data:create_file("read.lua", MODULE)

    local files = recording()
    dofile(read)
    dofile(read)

    assert.equal(1, #files.paths())
  end)

  it("hands the files back sorted, whatever order they were reached in", function()
    local later = helper.test_data:create_file("b.lua", MODULE)
    local earlier = helper.test_data:create_file("a.lua", MODULE)

    local files = recording()
    dofile(later)
    dofile(earlier)

    assert.same({ normalize(earlier), normalize(later) }, files.paths())
  end)

  it("records a file as the path Neovim spells it, whatever spelling it was read by", function()
    local read = helper.test_data:create_file("read.lua", MODULE)

    local files = recording()
    dofile(vim.fs.joinpath(helper.test_data.full_path, ".", "read.lua"))

    assert.same({ normalize(read) }, files.paths())
  end)

  it("records nothing once stopped, leaving the loaders as they were", function()
    local read = helper.test_data:create_file("read.lua", MODULE)
    local outer = { loadfile = loadfile, dofile = dofile, loaders = vim.list_slice(package.loaders) }

    local files = loaded.start(helper.test_data.full_path)
    files.stop()
    dofile(read)

    assert.same({}, files.paths())
    assert.equal(outer.loadfile, loadfile)
    assert.equal(outer.dofile, dofile)
    assert.same(outer.loaders, package.loaders)
  end)

  it("takes out its own searcher on stop and no other, wherever a later one pushed it", function()
    local outer = vim.list_slice(package.loaders)
    local files = loaded.start(helper.test_data.full_path)
    local later = function()
      return nil
    end
    table.insert(package.loaders, 1, later)

    files.stop()

    assert.equal(later, table.remove(package.loaders, 1))
    assert.same(outer, package.loaders)
  end)
end)
