local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local helper = require("ntf.test.helper")

--- @return { root: TSNode, src: string }[] # the parse of every lua source ntf ships
local function parses()
  local sources = vim.fn.globpath(vim.fs.joinpath(helper.root, "lua"), "**/*.lua", false, true)
  assert.is_true(#sources > 0)
  return vim.tbl_map(function(source)
    local src = table.concat(vim.fn.readfile(source), "\n")
    return { root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root(), src = src }
  end, sources)
end

--- @param node TSNode
--- @param visit fun(node: TSNode)
local function walk(node, visit)
  for child in node:iter_children() do
    visit(child)
    walk(child, visit)
  end
end

describe("lua grammar", function()
  it("gives an anonymous node no children, so a walk that skips one reaches no named descendant", function()
    local parents = {}
    for _, parse in ipairs(parses()) do
      walk(parse.root, function(node)
        if not node:named() and node:child_count() > 0 then
          table.insert(parents, node:type())
        end
      end)
    end

    assert.same({}, parents)
  end)

  it("spells every number node so that tonumber parses it", function()
    local unparsed = {}
    local numbers = 0
    for _, parse in ipairs(parses()) do
      walk(parse.root, function(node)
        if node:type() ~= "number" then
          return
        end
        numbers = numbers + 1
        local text = vim.treesitter.get_node_text(node, parse.src)
        if not tonumber(text) then
          table.insert(unparsed, text)
        end
      end)
    end

    assert.same({}, unparsed)
    assert.is_true(numbers > 0)
  end)
end)
