local ntf = require("ntf")
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local progress = require("ntf.core.controller.progress")

-- Collect everything the emitter writes so we can assert the plain stream.
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
  it("writes one character per finished test by status", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false, total = 4 })

    prog.on_item({}, item_of("passed", "failed", "error", "pending"))
    prog.finish()

    assert.equal(".FE*\n", table.concat(buf))
  end)

  it("inserts a done/total marker every width tests", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false, total = 5, width = 2 })

    prog.on_item({}, item_of("passed", "passed", "passed", "passed", "passed"))
    prog.finish()

    assert.equal(".. 2/5\n.. 4/5\n.\n", table.concat(buf))
  end)

  it("does not add a trailing newline when nothing ran", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false, total = 0 })

    prog.finish()

    assert.equal("", table.concat(buf))
  end)

  it("does not double the newline when the last write ended a line", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false, total = 2, width = 2 })

    prog.on_item({}, item_of("passed", "passed"))
    prog.finish()

    assert.equal(".. 2/2\n", table.concat(buf))
  end)

  it("paints failures red when color is enabled", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = true, total = 1 })

    prog.on_item({}, item_of("failed"))

    assert.equal("\27[31mF\27[0m", table.concat(buf))
  end)
end)
