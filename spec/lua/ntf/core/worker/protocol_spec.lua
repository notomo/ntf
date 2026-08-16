local ntf = require("ntf")
local describe, it, finally, assert = ntf.describe, ntf.it, ntf.finally, ntf.assert
local protocol = require("ntf.core.worker.protocol")

local NONCE = "0123456789abcdef0123456789abcdef"

local function emitted(result, nonce)
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
  protocol.emit(result, nonce or NONCE)
  io.stdout = saved
  return table.concat(written)
end

describe("ntf.core.worker.protocol emit -> parse", function()
  it("round-trips a result block through a worker's stdout", function()
    local stdout = "user output\n" .. emitted({ results = { { id = "1.1", status = "passed" } } })

    local decoded = protocol.parse(stdout, NONCE)
    assert.equal("1.1", decoded.results[1].id)
    assert.equal("passed", decoded.results[1].status)
  end)

  it("returns nil when the stdout has no result block", function()
    assert.is_nil(protocol.parse("just user output", NONCE))
    assert.is_nil(protocol.parse(nil, NONCE))
  end)

  it("ignores a block a test printed under another worker's nonce", function()
    local stdout = emitted({ results = { { id = "1.1", status = "passed" } } }, protocol.nonce())

    assert.is_nil(protocol.parse(stdout, NONCE))
  end)

  it("returns nil when the block between the markers is not JSON", function()
    local corrupted = emitted({ results = {} }):gsub("{.*}", "{ not json")

    assert.is_nil(protocol.parse(corrupted, NONCE))
  end)

  it("parses a result block that sits at the first byte of the stdout", function()
    local stdout = emitted({ results = { { id = "1.1", status = "passed" } } }):sub(2)

    assert.equal("1.1", protocol.parse(stdout, NONCE).results[1].id)
  end)

  it("returns nil when the worker died before writing the end marker", function()
    local truncated = emitted({ results = {} }):gsub("\n[^\n]+\n$", "")

    assert.is_nil(protocol.parse(truncated, NONCE))
  end)
end)

describe("ntf.core.worker.protocol.emit", function()
  it("writes the begin marker, the JSON, then the end marker, each on its own line", function()
    local lines = vim.split(emitted({ results = { { id = "1.1", status = "passed" } } }), "\n", { plain = true })

    assert.equal(5, #lines)
    assert.equal("", lines[1])
    assert.equal("1.1", vim.json.decode(lines[3]).results[1].id)
    assert.equal("", lines[5])
  end)

  it("surrounds the JSON with markers that hold no pattern-magic character", function()
    local lines = vim.split(emitted({ results = {} }, protocol.nonce()), "\n", { plain = true })

    for _, marker in ipairs({ lines[2], lines[4] }) do
      assert.is_true(#marker > 0)
      assert.equal(marker, (marker:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "")))
    end
  end)

  it("writes the worker's own nonce into both markers", function()
    local nonce = protocol.nonce()
    local lines = vim.split(emitted({ results = {} }, nonce), "\n", { plain = true })

    for _, marker in ipairs({ lines[2], lines[4] }) do
      assert.match(nonce, marker)
    end
  end)
end)

describe("ntf.core.worker.protocol.nonce", function()
  it("draws 16 bytes, written as the 32 hex characters a marker holds", function()
    local nonce = protocol.nonce()

    assert.equal(32, #nonce)
    assert.equal(nonce, nonce:match("^%x*$"))
  end)

  it("draws a different one per call", function()
    assert.is_true(protocol.nonce() ~= protocol.nonce())
  end)
end)

describe("ntf.core.worker.protocol.env -> payload", function()
  it("round-trips the payload through the worker's environment", function()
    local sent = { file = "/x_spec.lua", node_id = "1.1", coverage = false, cwd = "/tmp", nonce = NONCE }
    for name, value in pairs(protocol.env(sent)) do
      vim.env[name] = value
    end

    local received = protocol.payload()
    assert.equal("/x_spec.lua", received.file)
    assert.equal("1.1", received.node_id)
    assert.equal(NONCE, received.nonce)
  end)
end)

describe("ntf.core.worker.protocol.captured_output", function()
  it(
    "keeps only user writes: stdout before the result block, then stderr, where Neovim routes print and echo",
    function()
      local stdout = "written to stdout" .. emitted({ results = {} })

      assert.equal(
        "written to stdout\nprinted to stderr",
        protocol.captured_output(stdout, "printed to stderr\n", NONCE)
      )
    end
  )

  it("is empty when the worker wrote nothing of its own", function()
    assert.equal("", protocol.captured_output(emitted({ results = {} }), "", NONCE))
  end)

  it("is empty when the result block sits at the first byte of the stdout", function()
    assert.equal("", protocol.captured_output(emitted({ results = {} }):sub(2), "", NONCE))
  end)

  it("keeps the user's own trailing newline, dropping only emit's separator", function()
    local stdout = "written to stdout\n" .. emitted({ results = {} })

    assert.equal("written to stdout\n", protocol.captured_output(stdout, "", NONCE))
  end)

  it("keeps a block a test printed under another worker's nonce, which is output like any other", function()
    local printed = emitted({ results = {} }, protocol.nonce())

    assert.equal(printed:gsub("\n$", ""), protocol.captured_output(printed, "", NONCE))
  end)
end)
