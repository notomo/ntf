local ntf = require("ntf")
local describe, it, finally, assert = ntf.describe, ntf.it, ntf.finally, ntf.assert
local protocol = require("ntf.core.worker.protocol")

-- Run `emit` with stdout captured, returning what it wrote.
local function emitted(result)
  local written = {}
  local saved = io.stdout
  finally(function()
    io.stdout = saved
  end)
  io.stdout = {
    write = function(_, text)
      table.insert(written, text)
    end,
  }
  protocol.emit(result)
  io.stdout = saved
  return table.concat(written)
end

describe("ntf.core.worker.protocol emit -> parse", function()
  it("round-trips a result block through a worker's stdout", function()
    local stdout = "user output\n" .. emitted({ results = { { id = "1.1", status = "passed" } } })

    local decoded = protocol.parse(stdout)
    assert.equal("1.1", decoded.results[1].id)
    assert.equal("passed", decoded.results[1].status)
  end)

  it("returns nil when the stdout has no result block", function()
    assert.is_nil(protocol.parse("just user output"))
    assert.is_nil(protocol.parse(nil))
  end)
end)

describe("ntf.core.worker.protocol.env -> payload", function()
  it("round-trips the payload through the worker's environment", function()
    local sent = { file = "/x_spec.lua", node_id = "1.1", coverage = false, cwd = "/tmp" }
    for name, value in pairs(protocol.env(sent)) do
      vim.env[name] = value
    end

    local received = protocol.payload()
    assert.equal("/x_spec.lua", received.file)
    assert.equal("1.1", received.node_id)
  end)
end)

describe("ntf.core.worker.protocol.captured_output", function()
  it("keeps only user writes: stdout before the result block, then stderr", function()
    local stdout = "written to stdout" .. emitted({ results = {} })

    assert.equal("written to stdout\nprinted to stderr", protocol.captured_output(stdout, "printed to stderr\n"))
  end)

  it("is empty when the worker wrote nothing of its own", function()
    assert.equal("", protocol.captured_output(emitted({ results = {} }), ""))
  end)
end)
