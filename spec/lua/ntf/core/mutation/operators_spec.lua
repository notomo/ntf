local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")

--- @param src string
--- @return table[]
local function summarize(src)
  return vim.tbl_map(function(site)
    return { operator = site.operator, row = site.row, original = site.original, replacement = site.replacement }
  end, operators.enumerate(src))
end

describe("ntf.core.mutation.operators.enumerate", function()
  it("swaps relational operators", function()
    local sites = summarize([[
local _ = a == b
local _ = a ~= b
local _ = a < b
local _ = a <= b
local _ = a > b
local _ = a >= b
]])

    assert.same({
      { operator = "swap-relational", row = 1, original = "==", replacement = "~=" },
      { operator = "swap-relational", row = 2, original = "~=", replacement = "==" },
      { operator = "swap-relational", row = 3, original = "<", replacement = "<=" },
      { operator = "swap-relational", row = 4, original = "<=", replacement = "<" },
      { operator = "swap-relational", row = 5, original = ">", replacement = ">=" },
      { operator = "swap-relational", row = 6, original = ">=", replacement = ">" },
    }, sites)
  end)

  it("swaps logical operators", function()
    local sites = summarize([[
local _ = a and b
local _ = a or b
]])

    assert.same({
      { operator = "swap-logical", row = 1, original = "and", replacement = "or" },
      { operator = "swap-logical", row = 2, original = "or", replacement = "and" },
    }, sites)
  end)

  it("swaps binary arithmetic operators", function()
    local sites = summarize([[
local _ = a + b
local _ = a - b
]])

    assert.same({
      { operator = "swap-arith", row = 1, original = "+", replacement = "-" },
      { operator = "swap-arith", row = 2, original = "-", replacement = "+" },
    }, sites)
  end)

  it("leaves a unary minus alone", function()
    assert.same({}, summarize([[local _ = -a]]))
  end)

  it("flips boolean literals", function()
    local sites = summarize([[
local _ = true
local _ = false
]])

    assert.same({
      { operator = "flip-boolean", row = 1, original = "true", replacement = "false" },
      { operator = "flip-boolean", row = 2, original = "false", replacement = "true" },
    }, sites)
  end)

  it("drops `not` by replacing the whole unary expression with its operand", function()
    local sites = summarize([[local _ = not (a and b)]])

    assert.same({
      { operator = "drop-not", row = 1, original = "not (a and b)", replacement = "(a and b)" },
      { operator = "swap-logical", row = 1, original = "and", replacement = "or" },
    }, sites)
  end)

  it("perturbs number literals", function()
    local sites = summarize([[
local _ = 1
local _ = 1.5
local _ = 0x10
]])

    assert.same({
      { operator = "perturb-number", row = 1, original = "1", replacement = "2" },
      { operator = "perturb-number", row = 2, original = "1.5", replacement = "2.5" },
      { operator = "perturb-number", row = 3, original = "0x10", replacement = "17" },
    }, sites)
  end)

  it("finds no site in a string or a comment", function()
    local sites = summarize([[
-- a == b and 1
local _ = "a == b and 1"
]])

    assert.same({}, sites)
  end)

  it("carries the rows where the hit lands when the site executes", function()
    local sites = operators.enumerate(table.concat({
      "local _ = true",
      "f({",
      "  max = 20,",
      "})",
    }, "\n"))

    assert.same({ 1 }, sites[1].anchor_rows)
    assert.same({ 2 }, sites[2].anchor_rows)
  end)

  it("locates a site by both its position and its byte range", function()
    local src = [[
local _ = a
  == b
]]

    local site = operators.enumerate(src)[1]

    assert.same({
      row = 2,
      col = 2,
      end_row = 2,
      end_col = 4,
      start_byte = 14,
      end_byte = 16,
    }, {
      row = site.row,
      col = site.col,
      end_row = site.end_row,
      end_col = site.end_col,
      start_byte = site.start_byte,
      end_byte = site.end_byte,
    })
    assert.equal("==", src:sub(site.start_byte + 1, site.end_byte))
  end)

  it("sorts sites by position", function()
    local sites = summarize([[local _ = 1 + 2 == 3]])

    assert.same({ "perturb-number", "swap-arith", "perturb-number", "swap-relational", "perturb-number" }, {
      sites[1].operator,
      sites[2].operator,
      sites[3].operator,
      sites[4].operator,
      sites[5].operator,
    })
  end)

  it("returns sites whose mutated source still compiles", function()
    local src = [[
local function f(a, b)
  if a == b and not a then
    return a + 1, true
  end
  return a < b or false
end
return f
]]

    local sites = operators.enumerate(src)
    assert.equal(9, #sites)
    for _, site in ipairs(sites) do
      local mutated = assert(splice.apply(src, site))
      assert(loadstring(mutated), ("uncompilable mutant: %s"):format(site.operator))
    end
  end)
end)
