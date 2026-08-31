local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local lines = require("ntf.core.coverage.lines")

--- @param src string
--- @return integer[] # the rows a statement starts on, ascending
local function rows(src)
  return vim.tbl_map(function(statement)
    return statement.row
  end, lines.statements(src))
end

describe("ntf.core.coverage.lines.statements", function()
  it("takes each statement of a block in the order it is written", function()
    local src = table.concat({
      "local function f(t)",
      "  if t.a then",
      "    return 0",
      "  end",
      "  while t.b do",
      "    break",
      "  end",
      "  repeat",
      "    t.c = 1",
      "  until t.c",
      "  for i = 1, 2 do",
      "    t[i] = i",
      "  end",
      "  for _, v in pairs(t) do",
      "    t.d = v",
      "  end",
      "  do",
      "    goto done",
      "  end",
      "  ::done::",
      "end",
    }, "\n")

    assert.same({ 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20 }, rows(src))
  end)

  it("takes a statement of the chunk itself, which no block holds", function()
    local src = table.concat({
      "local M = {}",
      "return M",
    }, "\n")

    assert.same({ 1, 2 }, rows(src))
  end)

  it("takes each of the statements a single row holds", function()
    assert.same({ 1, 1 }, rows("local a = 1 return a"))
  end)

  it("takes a statement at the byte it starts at, ascending, as splicing counters in relies on", function()
    local src = table.concat({
      "local function f()",
      "  return 1",
      "end",
      "return f",
    }, "\n")

    local bytes = vim.tbl_map(function(statement)
      return statement.byte
    end, lines.statements(src))

    assert.same({ 0, 21, 34 }, bytes)
  end)

  it("takes no statement out of an expression that only looks like one", function()
    local call_of_a_call = "local x = f(g())"

    assert.same({ 1 }, rows(call_of_a_call))
  end)

  it("takes a bare `;` as the statement it is", function()
    local src = table.concat({
      "local x = 1",
      ";",
      "return x",
    }, "\n")

    assert.same({ 1, 2, 3 }, rows(src))
  end)

  it("takes nothing out of a source that holds no statement", function()
    assert.same({}, rows("-- nothing to run here"))
  end)
end)

describe("ntf.core.coverage.lines.coverable", function()
  it("counts the row each statement starts on, once however many start there", function()
    local src = table.concat({
      "local a = 1 local b = 2",
      "local function f()",
      "  return a + b",
      "end",
      "return f",
    }, "\n")

    assert.same({ [1] = true, [2] = true, [3] = true, [5] = true }, lines.coverable(src))
  end)

  it("counts no row a statement merely continues onto", function()
    local src = table.concat({
      "local x = vim",
      "  .iter({})",
      "  :totable()",
    }, "\n")

    local coverable = lines.coverable(src)
    assert.is_true(coverable[1])
    assert.is_nil(coverable[2])
    assert.is_nil(coverable[3])
  end)
end)

describe("ntf.core.coverage.lines.anchor_rows", function()
  --- @return TSNode
  local function node_at(src, row, col)
    local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()
    local node = root:named_descendant_for_range(row, col, row, col)
    return assert(node)
  end

  it("anchors a constant table field to the row the statement holding it starts on", function()
    local src = table.concat({
      "f({",
      "  strict = false,",
      "})",
    }, "\n")

    assert.same({ 1 }, lines.anchor_rows(node_at(src, 1, 11)))
  end)

  it("anchors a value of a multi-row statement to the row the statement starts on", function()
    local src = table.concat({
      "local function f()",
      "  return {",
      "    strict = false,",
      "  }",
      "end",
    }, "\n")

    assert.same({ 2 }, lines.anchor_rows(node_at(src, 2, 13)))
  end)

  it("anchors a statement of a closure to itself, not to the statement the closure is written in", function()
    local src = table.concat({
      "local x = function()",
      "  return 1",
      "end",
    }, "\n")

    assert.same({ 2 }, lines.anchor_rows(node_at(src, 1, 9)))
  end)

  it("anchors a call that is a statement of its own to its own row", function()
    local src = table.concat({
      "f(1)",
      "g(2)",
    }, "\n")

    assert.same({ 2 }, lines.anchor_rows(node_at(src, 1, 2)))
  end)

  it("returns no anchor for what no statement holds", function()
    assert.same({}, lines.anchor_rows(node_at("-- a comment", 0, 3)))
  end)
end)
