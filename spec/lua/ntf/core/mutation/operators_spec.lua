local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local operators = require("ntf.core.mutation.operators")
local splice = require("ntf.core.mutation.splice")

local EVERY_OPERATOR_SOURCE = [[
local function f(a, b)
  if a == b and not a then
    return -a + 1, true
  end
  g(a)
  h.x = a
  return a < b or false
end
return f
]]

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
local _ = a * b
local _ = a / b
local _ = a % b
local _ = a ^ b
]])

    assert.same({
      { operator = "swap-arith", row = 1, original = "+", replacement = "-" },
      { operator = "swap-arith", row = 2, original = "-", replacement = "+" },
      { operator = "swap-arith", row = 3, original = "*", replacement = "/" },
      { operator = "swap-arith", row = 4, original = "/", replacement = "*" },
      { operator = "swap-arith", row = 5, original = "%", replacement = "*" },
      { operator = "swap-arith", row = 6, original = "^", replacement = "*" },
    }, sites)
  end)

  it("leaves floor division alone, since the runtime that loads a mutant cannot compile it", function()
    local src = [[local _ = a // b]]

    assert(not loadstring(src))
    assert.same({}, summarize(src))
  end)

  it("drops a unary minus by replacing the whole unary expression with its operand", function()
    local sites = summarize([[local _ = b - -(a + 1)]])

    assert.same({
      { operator = "swap-arith", row = 1, original = "-", replacement = "+" },
      { operator = "drop-neg", row = 1, original = "-(a + 1)", replacement = "(a + 1)" },
      { operator = "swap-arith", row = 1, original = "+", replacement = "-" },
      { operator = "perturb-number", row = 1, original = "1", replacement = "2" },
    }, sites)
  end)

  it("leaves the length operator alone", function()
    assert.same({}, summarize([[local _ = #a]]))
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

  it("forces each branch of an if/elseif chain to both outcomes", function()
    local sites = summarize([[
if a == b then
elseif c then
else
end
]])

    assert.same({
      { operator = "force-branch", row = 1, original = "a == b", replacement = "false" },
      { operator = "force-branch", row = 1, original = "a == b", replacement = "true" },
      { operator = "swap-relational", row = 1, original = "==", replacement = "~=" },
      { operator = "force-branch", row = 2, original = "c", replacement = "false" },
      { operator = "force-branch", row = 2, original = "c", replacement = "true" },
    }, sites)
  end)

  it("forces a while condition to false only, never the infinite true", function()
    local sites = summarize([[while a < b do end]])

    assert.same({
      { operator = "force-branch", row = 1, original = "a < b", replacement = "false" },
      { operator = "swap-relational", row = 1, original = "<", replacement = "<=" },
    }, sites)
  end)

  it("forces a repeat condition to true only, never the infinite false", function()
    local sites = summarize([[repeat until a < b]])

    assert.same({
      { operator = "force-branch", row = 1, original = "a < b", replacement = "true" },
      { operator = "swap-relational", row = 1, original = "<", replacement = "<=" },
    }, sites)
  end)

  it("forces a for to the clause that iterates none, whether it counts or walks", function()
    local sites = summarize([[
for i = 1, n do end
for i = 1, n, 2 do end
for k, v in pairs(t) do end
for x in f do end
]])

    assert.same({
      { operator = "force-branch", row = 1, original = "i = 1, n", replacement = "_ = 1, 0" },
      { operator = "perturb-number", row = 1, original = "1", replacement = "2" },
      { operator = "force-branch", row = 2, original = "i = 1, n, 2", replacement = "_ = 1, 0" },
      { operator = "perturb-number", row = 2, original = "1", replacement = "2" },
      { operator = "perturb-number", row = 2, original = "2", replacement = "3" },
      { operator = "force-branch", row = 3, original = "k, v in pairs(t)", replacement = "_ in pairs({})" },
      { operator = "force-branch", row = 4, original = "x in f", replacement = "_ in pairs({})" },
    }, sites)
  end)

  it("takes the whole for clause, so the loop it heads never enters its body", function()
    local src = "for i = 1, n do f(i) end"

    local site = operators.enumerate(src)[1]

    assert.equal("force-branch", site.operator)
    assert.equal("for _ = 1, 0 do f(i) end", splice.apply(src, site))
  end)

  it("leaves a bare boolean condition to flip-boolean, forcing no branch", function()
    local sites = summarize([[
if true then
end
]])

    assert.same({
      { operator = "flip-boolean", row = 1, original = "true", replacement = "false" },
    }, sites)
  end)

  it("deletes a call that stands as a statement, whatever it is called through", function()
    local sites = summarize([[
f()
a.b:c()
require("x")
do
  d{}
end
]])

    assert.same({
      { operator = "delete-call", row = 1, original = "f()", replacement = "do end" },
      { operator = "delete-call", row = 2, original = "a.b:c()", replacement = "do end" },
      { operator = "delete-call", row = 3, original = 'require("x")', replacement = "do end" },
      { operator = "delete-call", row = 5, original = "d{}", replacement = "do end" },
    }, sites)
  end)

  it("leaves a call whose value is used, since deleting it takes the expression with it", function()
    local sites = summarize([[
local _ = g()
local _ = { k = h() }
]])

    assert.same({}, sites)
  end)

  it("takes a call chain whole, since the call it chains onto is not a statement of its own", function()
    local src = table.concat({
      "local a = b",
      "f()",
      "(g)()",
    }, "\n")

    local site = operators.enumerate(src)[1]

    assert.equal("delete-call", site.operator)
    assert.equal("local a = b\ndo end", splice.apply(src, site))
  end)

  it("deletes an assignment that stands as a statement, whatever it stores into", function()
    local sites = summarize([[
x = a
t.k = a
t[k] = a
t.k, t[j] = a, b
do
  t.k = a
end
]])

    assert.same({
      { operator = "delete-assign", row = 1, original = "x = a", replacement = "do end" },
      { operator = "delete-assign", row = 2, original = "t.k = a", replacement = "do end" },
      { operator = "delete-assign", row = 3, original = "t[k] = a", replacement = "do end" },
      { operator = "delete-assign", row = 4, original = "t.k, t[j] = a, b", replacement = "do end" },
      { operator = "delete-assign", row = 6, original = "t.k = a", replacement = "do end" },
    }, sites)
  end)

  it("leaves a local declaration, whose deletion would rewrite the scope and not the store", function()
    local sites = summarize([[
local x = a
local y
y = a
]])

    assert.same({
      { operator = "delete-assign", row = 3, original = "y = a", replacement = "do end" },
    }, sites)
  end)

  it("takes the assignment whole, so the call that gives it its value goes with it", function()
    local src = "t.k = f()"

    local site = operators.enumerate(src)[1]

    assert.equal("delete-assign", site.operator)
    assert.equal("do end", splice.apply(src, site))
  end)

  it("drops what a function answers, however many values the return lists", function()
    local sites = summarize([[
local function f()
  return a
end
function M.g()
  return a, b
end
local h = function()
  do
    return b
  end
end
]])

    assert.same({
      { operator = "drop-return", row = 2, original = "a", replacement = "nil" },
      { operator = "drop-return", row = 5, original = "a, b", replacement = "nil" },
      { operator = "drop-return", row = 9, original = "b", replacement = "nil" },
    }, sites)
  end)

  it("leaves the return a chunk answers with, which is the module rather than an answer", function()
    local sites = summarize([[
local function f()
  return a
end
do
  return f
end
]])

    assert.same({
      { operator = "drop-return", row = 2, original = "a", replacement = "nil" },
    }, sites)
  end)

  it("leaves a return of one literal to the operator that owns the literal", function()
    local sites = summarize([[
local function f()
  return nil
end
local function g()
  return true
end
local function h()
  return false
end
local function i()
  return 1
end
]])

    assert.same({
      { operator = "flip-boolean", row = 5, original = "true", replacement = "false" },
      { operator = "flip-boolean", row = 8, original = "false", replacement = "true" },
      { operator = "perturb-number", row = 11, original = "1", replacement = "2" },
    }, sites)
  end)

  it("takes a return of a literal among others, which no single literal's operator empties", function()
    local sites = summarize([[
local function f()
  return nil, err
end
]])

    assert.same({
      { operator = "drop-return", row = 2, original = "nil, err", replacement = "nil" },
    }, sites)
  end)

  it("finds no site in a return that gives nothing back", function()
    local sites = summarize([[
local function f()
  return
end
]])

    assert.same({}, sites)
  end)

  it("leaves the semicolon of a return, taking only the values", function()
    local src = "local function f() return g; end"

    local site = operators.enumerate(src)[1]

    assert.equal("drop-return", site.operator)
    assert.equal("local function f() return nil; end", splice.apply(src, site))
  end)

  it("anchors a return of a closure on the row its hit lands, not on the return", function()
    local sites = operators.enumerate(table.concat({
      "local function f()",
      "  return function()",
      "    g()",
      "  end",
      "end",
    }, "\n"))

    assert.equal("drop-return", sites[1].operator)
    assert.same({ 4 }, sites[1].anchor_rows)
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

  it("sorts sites that start at one byte by operator name, so the order never rests on the walk", function()
    local sites = summarize([[local function f() return -a end]])

    assert.same({
      { operator = "drop-neg", row = 1, original = "-a", replacement = "a" },
      { operator = "drop-return", row = 1, original = "-a", replacement = "nil" },
    }, sites)
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
    local sites = operators.enumerate(EVERY_OPERATOR_SOURCE)
    assert.equal(16, #sites)
    for _, site in ipairs(sites) do
      local mutated = assert(splice.apply(EVERY_OPERATOR_SOURCE, site))
      assert(loadstring(mutated), ("uncompilable mutant: %s"):format(site.operator))
    end
  end)
end)

describe("ntf.core.mutation.operators.operators", function()
  --- @param names string[]
  --- @return string[]
  local function sorted(names)
    local sorted_names = vim.deepcopy(names)
    table.sort(sorted_names)
    return sorted_names
  end

  it("declares the operators enumerate produces, and no others", function()
    local produced = {}
    for _, site in ipairs(operators.enumerate(EVERY_OPERATOR_SOURCE)) do
      produced[site.operator] = true
    end

    local declared = vim.tbl_map(function(operator)
      return operator.name
    end, operators.operators)

    assert.same(sorted(vim.tbl_keys(produced)), sorted(declared))
  end)

  it("gives each operator an example whose every site is that operator's", function()
    for _, operator in ipairs(operators.operators) do
      local sites = operators.enumerate(operator.example)
      assert(#sites > 0, ("no site in the example of %s: %s"):format(operator.name, operator.example))
      for _, site in ipairs(sites) do
        assert.equal(operator.name, site.operator)
      end
    end
  end)
end)

describe("ntf.core.mutation.operators.validate_selection", function()
  local needs = "needs an array"

  it('accepts "all"', function()
    assert.is_nil(operators.validate_selection("all", needs))
  end)

  it("accepts an array naming a single operator", function()
    assert.is_nil(operators.validate_selection({ "swap-relational" }, needs))
  end)

  it("accepts an array naming several operators", function()
    assert.is_nil(operators.validate_selection({ "swap-relational", "force-branch" }, needs))
  end)

  it("says what it needs when given nothing at all, which no default stands in for", function()
    assert.equal(needs, operators.validate_selection(nil, needs))
  end)

  it("says what it needs when given a string that is not all", function()
    assert.equal(needs, operators.validate_selection("every", needs))
  end)

  it("says what it needs when given an empty array, which names no operator at all", function()
    assert.equal(needs, operators.validate_selection({}, needs))
  end)

  it("rejects a name no operator answers to, which is how a typo is caught", function()
    assert.match(
      'names an operator no run produces: "swap%-relatinal"',
      operators.validate_selection({ "swap-relatinal" }, needs)
    )
  end)

  it("rejects a name that is not a string", function()
    assert.match("names an operator no run produces: 3", operators.validate_selection({ 3 }, needs))
  end)
end)

describe("ntf.core.mutation.operators.adopted", function()
  it('takes every operator under "all"', function()
    local adopted = operators.adopted("all")

    assert.is_true(adopted("swap-relational"))
    assert.is_true(adopted("force-branch"))
  end)

  it("takes only the operators an array names", function()
    local adopted = operators.adopted({ "swap-relational" })

    assert.is_true(adopted("swap-relational"))
    assert.is_false(adopted("force-branch"))
  end)

  it("takes each of the operators an array names", function()
    local adopted = operators.adopted({ "swap-relational", "force-branch" })

    assert.is_true(adopted("swap-relational"))
    assert.is_true(adopted("force-branch"))
  end)
end)
