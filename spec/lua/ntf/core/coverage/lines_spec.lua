local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local lines = require("ntf.core.coverage.lines")

describe("ntf.core.coverage.lines.coverable", function()
  it("counts a control statement's own opening line", function()
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
      "  goto done",
      "  ::done::",
      "end",
    }, "\n")

    local coverable = lines.coverable(src)
    assert.same(
      { true, true, true, true, true, true, true },
      vim.tbl_map(function(row)
        return coverable[row]
      end, { 2, 5, 6, 8, 11, 14, 17 })
    )
  end)

  it("keeps a return of a plain binary expression coverable", function()
    local src = table.concat({
      "local function f(a, b)",
      "  return a + b",
      "end",
    }, "\n")

    assert.is_true(lines.coverable(src)[2])
  end)

  it("does not count a line whose only values are closures", function()
    local src = table.concat({
      "local x",
      "x = nil or function()",
      "  return 1",
      "end",
    }, "\n")

    assert.is_nil(lines.coverable(src)[2])
  end)

  it("does not count a line whose comma-separated values are all closures", function()
    local src = table.concat({
      "local a, b = function()",
      "  return 1",
      "end, function()",
      "  return 2",
      "end",
    }, "\n")

    assert.is_nil(lines.coverable(src)[1])
  end)

  it("counts a line that mixes a non-closure value with a closure", function()
    local src = table.concat({
      "local a, b = 1, function()",
      "  return 1",
      "end",
    }, "\n")

    assert.is_true(lines.coverable(src)[1])
  end)

  it("counts an assignment whose closure is parenthesized", function()
    local src = table.concat({
      "local x = (function()",
      "  return 1",
      "end)",
    }, "\n")

    assert.is_true(lines.coverable(src)[1])
  end)
end)

describe("ntf.core.coverage.lines.anchor_rows", function()
  --- @return TSNode
  local function node_at(src, row, col)
    local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()
    local node = root:named_descendant_for_range(row, col, row, col)
    return assert(node)
  end

  it("anchors a constant table field to the call's `(` line", function()
    local src = table.concat({
      "f({",
      "  strict = false,",
      "})",
    }, "\n")

    assert.same({ 1 }, lines.anchor_rows(node_at(src, 1, 11)))
  end)

  it("anchors a constant table field to the returning statement's line", function()
    local src = table.concat({
      "local function f()",
      "  return {",
      "    strict = false,",
      "  }",
      "end",
    }, "\n")

    assert.same({ 2 }, lines.anchor_rows(node_at(src, 2, 13)))
  end)

  it(
    "anchors a closure-only statement to its own closing `end`, not to an enclosing block that runs whether or not the closure is called",
    function()
      local src = table.concat({
        "local x",
        "x = nil or function()",
        "  return 1",
        "end",
      }, "\n")

      assert.same({ 4 }, lines.anchor_rows(node_at(src, 1, 4)))
    end
  )

  it("returns no anchor without a hit-receiving ancestor", function()
    assert.same({}, lines.anchor_rows(node_at("local x", 0, 6)))
  end)
end)
