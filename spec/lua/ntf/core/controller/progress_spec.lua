local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local progress = require("ntf.core.controller.progress")

local function collector()
  local buf = {}
  return buf, function(s)
    table.insert(buf, s)
  end
end

local function item_of(...)
  local results = {}
  for _, status in ipairs({ ... }) do
    table.insert(results, { status = status })
  end
  return results
end

describe("ntf.core.controller.progress", function()
  it("writes one character per finished test by status, with no count marker", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false })

    prog.on_item({}, item_of("passed", "failed", "error", "pending"))
    prog.finish()

    assert.equal(".FE*\n", table.concat(buf))
  end)

  it("does not add a trailing newline when nothing ran", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false })

    prog.finish()

    assert.equal("", table.concat(buf))
  end)

  it("closes the current dot line via newline so the next block starts fresh", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false })

    prog.on_item({}, item_of("passed", "passed"))
    prog.newline()
    -- a second newline with nothing pending must not double the break
    prog.newline()
    prog.on_item({}, item_of("passed"))
    prog.finish()

    assert.equal("..\n.\n", table.concat(buf))
  end)

  it("paints failures red when color is enabled", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = true })

    prog.on_item({}, item_of("failed"))

    assert.equal("\27[31mF\27[0m", table.concat(buf))
  end)
end)
