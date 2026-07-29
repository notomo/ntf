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

  it("closes the current dot line via newline, and a second one with nothing pending adds no break", function()
    local buf, write = collector()
    local prog = progress.new({ write = write, color = false })

    prog.on_item({}, item_of("passed", "passed"))
    prog.newline()
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

describe("ntf.core.controller.progress.mutation", function()
  it("writes the total, one character per settled mutant, then a closing newline", function()
    local buf, write = collector()
    local prog = progress.mutation({ write = write, enabled = true, color = false })

    prog.on_start(4)
    prog.on_task({ status = "killed" })
    prog.on_task({ status = "timeout" })
    prog.on_task({ status = "survived" })
    prog.on_task({ status = "not_applied" })
    prog.finish()

    assert.equal("mutants (4): .TS?\n", table.concat(buf))
  end)

  it("writes nothing at all when disabled", function()
    local buf, write = collector()
    local prog = progress.mutation({ write = write, enabled = false, color = true })

    prog.on_start(2)
    prog.on_task({ status = "survived" })
    prog.finish()

    assert.equal("", table.concat(buf))
  end)

  it("paints a survivor red when color is enabled, leaving a mark with no color of its own bare", function()
    local buf, write = collector()
    local prog = progress.mutation({ write = write, enabled = true, color = true })

    prog.on_task({ status = "survived" })
    prog.on_task({ status = "killed" })

    assert.equal("\27[31mS\27[0m.", table.concat(buf))
  end)

  it("leaves a survivor bare when color is disabled", function()
    local buf, write = collector()
    local prog = progress.mutation({ write = write, enabled = true, color = false })

    prog.on_task({ status = "survived" })

    assert.equal("S", table.concat(buf))
  end)

  it("marks an outcome it has no character for as a survivor, the one that must not go unseen", function()
    local buf, write = collector()
    local prog = progress.mutation({ write = write, enabled = true, color = false })

    prog.on_task({ status = "no_coverage" })

    assert.equal("S", table.concat(buf))
  end)
end)
