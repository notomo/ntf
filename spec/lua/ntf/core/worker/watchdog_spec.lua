local ntf = require("ntf")
local describe, before_each, after_each, it, assert = ntf.describe, ntf.before_each, ntf.after_each, ntf.it, ntf.assert
local watchdog = require("ntf.core.worker.watchdog")
local helper = require("ntf.test.helper")

describe("ntf.core.worker.watchdog.deadline", function()
  it("outlives the timeout the run would kill the worker at", function()
    assert.equal(31000, watchdog.deadline(1000))
  end)
end)

describe("ntf.core.worker.watchdog.start", function()
  before_each(helper.before_each)
  after_each(helper.after_each)

  it("kills a process spinning in lua, which no timer of its own could reach", function()
    local script = helper.test_data:create_file(
      "spinner.lua",
      ([[
vim.opt.runtimepath:prepend(%q)
require("ntf.core.worker.watchdog").start(500)
while true do end
]]):format(helper.root)
    )

    local obj = vim
      .system({
        vim.v.progpath,
        "--clean",
        "--headless",
        "-c",
        ("lua vim.cmd.luafile({ args = { %q }, magic = { file = false } })"):format(script),
      }, { text = true })
      :wait(30000)

    assert.equal(9, obj.signal)
  end)
end)
