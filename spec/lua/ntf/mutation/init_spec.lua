local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local mutation = require("ntf.mutation")
local cache_path = require("ntf.core.cache_path")
local helper = require("ntf.test.helper")

local SOURCE = table.concat({
  "local M = {}",
  "function M.f(a, b)",
  "  return a < b",
  "end",
  "return M",
}, "\n")

--- @param row integer 1-based
--- @param status string
local function record(row, status)
  return {
    row = row,
    col = 9,
    end_row = row,
    end_col = 10,
    operator = "swap-relational",
    original = "<",
    replacement = "<=",
    status = status,
  }
end

--- @param bufnr integer
--- @return table[]
local function diagnostics(bufnr)
  return vim
    .iter(vim.diagnostic.get(bufnr, { namespace = mutation.namespace() }))
    :map(function(diagnostic)
      return {
        lnum = diagnostic.lnum,
        col = diagnostic.col,
        end_lnum = diagnostic.end_lnum,
        end_col = diagnostic.end_col,
        severity = diagnostic.severity,
        source = diagnostic.source,
        code = diagnostic.code,
        message = diagnostic.message,
      }
    end)
    :totable()
end

--- @param bufnr integer
--- @return string[] # the lines drawn under the code, whichever namespace draws them
local function virtual_lines(bufnr)
  local drawn = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      local texts = {}
      for _, chunk in ipairs(line) do
        table.insert(texts, chunk[1])
      end
      table.insert(drawn, table.concat(texts))
    end
  end
  return drawn
end

--- @param row integer 1-based
local function survivor(row)
  return {
    lnum = row - 1,
    col = 9,
    end_lnum = row - 1,
    end_col = 10,
    severity = vim.diagnostic.severity.WARN,
    source = "ntf",
    code = "swap-relational",
    message = "<=",
  }
end

--- @param records table[]
--- @return string src, string results_file
local function project(records)
  local src = helper.test_data:create_file("mod.lua", SOURCE)
  local file = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
  local results_file = helper.test_data:create_file(
    "ntf-mutation.json",
    vim.json.encode({
      version = 1,
      score = 50,
      counts = { killed = 1, timeout = 0, survived = 1, no_coverage = 0, not_applied = 0 },
      files = { [file] = records },
    })
  )
  return src, results_file
end

describe("ntf.mutation.decorate", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("marks the surviving mutants with the change they got away with", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({ survivor(3) }, diagnostics(bufnr))
  end)

  it("marks each survivor sharing a line, over the code each one changed", function()
    local shared_row = 3
    local second = record(shared_row, "survived")
    second.col = 11
    second.end_col = 12
    second.operator = "drop-return-value"
    second.original = "b"
    second.replacement = "nil"
    local src, results_file = project({ record(shared_row, "survived"), second })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({
      survivor(shared_row),
      {
        lnum = shared_row - 1,
        col = 11,
        end_lnum = shared_row - 1,
        end_col = 12,
        severity = vim.diagnostic.severity.WARN,
        source = "ntf",
        code = "drop-return-value",
        message = "nil",
      },
    }, diagnostics(bufnr))
  end)

  it("underlines a survivor that changed more than one line, message on one line", function()
    local multi_line = record(2, "survived")
    multi_line.end_row = 4
    multi_line.col = 0
    multi_line.end_col = 3
    multi_line.operator = "drop-not"
    multi_line.original = "not (a\n  < b)"
    multi_line.replacement = "(a\n  < b)"
    local src, results_file = project({ multi_line })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({
      {
        lnum = 1,
        col = 0,
        end_lnum = 3,
        end_col = 3,
        severity = vim.diagnostic.severity.WARN,
        source = "ntf",
        code = "drop-not",
        message = "(a < b)",
      },
    }, diagnostics(bufnr))
  end)

  it("cuts a replacement too wide for a buffer to carry", function()
    local wide = record(3, "survived")
    wide.operator = "drop-not"
    wide.replacement = ("a"):rep(80)
    local src, results_file = project({ wide })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.equal(("a"):rep(59) .. "…", diagnostics(bufnr)[1].message)
  end)

  it("marks a survivor sitting on the buffer's last line", function()
    local last_line = 5
    local src, results_file = project({ record(last_line, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({ survivor(last_line) }, diagnostics(bufnr))
  end)

  it("decorates the current buffer, not the first one, when no buffer is given", function()
    local src, results_file = project({ record(3, "survived") })
    vim.cmd.edit(helper.test_data:create_file("decoy.lua", SOURCE))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file })

    assert.same({ survivor(3) }, diagnostics(bufnr))
  end)

  it("sets nothing for a mutant the tests detected", function()
    local src, results_file = project({ record(3, "killed"), record(1, "no_coverage") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({}, diagnostics(bufnr))
  end)

  it("sets nothing past the buffer's end when the results are stale", function()
    local src, results_file = project({ record(99, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({}, diagnostics(bufnr))
  end)

  it("sets nothing for a buffer the results do not mention", function()
    local _, results_file = project({ record(3, "survived") })
    local other = helper.test_data:create_file("other.lua", SOURCE)

    vim.cmd.edit(other)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.same({}, diagnostics(bufnr))
  end)

  it("replaces what an earlier run left, so a fixed survivor stops being marked", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    local _, second_results_file = project({ record(3, "killed") })
    mutation.decorate({ path = second_results_file, buffer = bufnr })

    assert.same({}, diagnostics(bufnr))
  end)

  it("clears the decoration when disabled, from the first line through the last", function()
    local first_line, last_line = 1, 5
    local src, results_file = project({ record(first_line, "survived"), record(last_line, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })
    mutation.decorate({ path = results_file, buffer = bufnr, enable = false })

    assert.same({}, diagnostics(bufnr))
  end)

  it("reads no results file at all when disabled", function()
    local path = helper.test_data:path("nope.json")

    mutation.decorate({ path = path, enable = false })

    assert.same({}, diagnostics(0))
  end)

  it("clears the decoration before it reads, so a results file that is gone leaves none behind", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    local missing = helper.test_data:path("nope.json")
    assert.is_false(pcall(mutation.decorate, { path = missing, buffer = bufnr }))
    assert.same({}, diagnostics(bufnr))
  end)

  it("reads the default results path when called with no options at all", function()
    helper.test_data:cd("")

    local ok, err = pcall(mutation.decorate)

    assert.is_false(ok)
    assert.equal(
      "[ntf] mutation results file is not found: "
        .. vim.fs.normalize(vim.fn.fnamemodify(cache_path.mutation_results(), ":p")),
      err
    )
  end)

  it("errors, unprefixed, when the results file does not exist", function()
    local path = helper.test_data:path("nope.json")

    local ok, err = pcall(mutation.decorate, { path = path })

    assert.is_false(ok)
    assert.equal("[ntf] mutation results file is not found: " .. vim.fs.normalize(path), err)
  end)
end)

describe("ntf.mutation.is_decorated", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("finds a decoration set on the buffer's first line", function()
    local src, results_file = project({ record(1, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = bufnr })

    assert.is_true(mutation.is_decorated({ buffer = bufnr }))
  end)

  it("reports on the current buffer, not the first one, when no buffer is given", function()
    local src, results_file = project({ record(3, "survived") })
    vim.cmd.edit(helper.test_data:create_file("decoy.lua", SOURCE))

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    assert.is_false(mutation.is_decorated())

    mutation.decorate({ path = results_file, buffer = bufnr })
    assert.is_true(mutation.is_decorated())
  end)

  it("reports per buffer", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local decorated = vim.api.nvim_get_current_buf()
    mutation.decorate({ path = results_file, buffer = decorated })
    local other = vim.api.nvim_create_buf(false, true)

    assert.is_true(mutation.is_decorated({ buffer = decorated }))
    assert.is_false(mutation.is_decorated({ buffer = other }))
  end)

  it("is true only while the decoration is set", function()
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    assert.is_false(mutation.is_decorated({ buffer = bufnr }))

    mutation.decorate({ path = results_file, buffer = bufnr })
    assert.is_true(mutation.is_decorated({ buffer = bufnr }))

    mutation.decorate({ path = results_file, buffer = bufnr, enable = false })
    assert.is_false(mutation.is_decorated({ buffer = bufnr }))
  end)
end)

describe("ntf.mutation.namespace", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("is the diagnostic namespace the survivors are set in", function()
    assert.equal(vim.api.nvim_create_namespace("ntf.mutation"), mutation.namespace())
  end)

  it("shows the survivors as a sign and as virtual lines, never as end-of-line text", function()
    assert.same({
      signs = { text = { [vim.diagnostic.severity.WARN] = "▌" } },
      virtual_text = false,
      virtual_lines = { current_line = false },
    }, vim.diagnostic.config(nil, mutation.namespace()))
  end)

  it("draws a survivor as soon as it is set, wherever the cursor is", function()
    vim.diagnostic.config({ virtual_lines = { current_line = true } })
    local src, results_file = project({ record(3, "survived") })

    vim.cmd.edit(src)
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    mutation.decorate({ path = results_file, buffer = bufnr })

    local drawn = virtual_lines(bufnr)
    assert.equal(1, #drawn)
    assert.match("swap%-relational: <=", drawn[1])
  end)
end)

describe("ntf.mutation.results_path", function()
  it("is the file a run in the current directory writes", function()
    assert.equal(cache_path.mutation_results(), mutation.results_path())
  end)

  it("takes the directory the run was made from", function()
    local dir = vim.fs.dirname(vim.fn.getcwd())

    assert.equal(cache_path.mutation_results(dir), mutation.results_path({ working_dir = dir }))
  end)
end)
