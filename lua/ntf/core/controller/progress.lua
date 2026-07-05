-- Streaming progress for the controller: one character per finished test,
-- written to stderr as workers complete, so a long (or hung) run shows it is
-- alive instead of staying silent until the final report. Plain dots only, no
-- in-place `\r` redraw, so it survives non-tty capture (agents, CI) too.
local M = {}

local COLORS = {
  red = "\27[31m",
  yellow = "\27[33m",
  reset = "\27[0m",
}

--- @type table<string, { [1]: string, [2]: ("red"|"yellow")? }> status -> mark char and color
local MARKS = {
  passed = { "." },
  failed = { "F", "red" },
  error = { "E", "red" },
  pending = { "*", "yellow" },
}

--- @param opts { write: fun(text: string), color: boolean }
--- @return { on_item: fun(item: NtfWorkItem, results: NtfResult[]), newline: fun(), finish: fun() }
function M.new(opts)
  local write = opts.write
  local color = opts.color

  local at_line_start = true

  local function paint(name, text)
    if not color or not name then
      return text
    end
    return COLORS[name] .. text .. COLORS.reset
  end

  local function on_item(_, results)
    for _, result in ipairs(results) do
      local mark = MARKS[result.status] or MARKS.error
      write(paint(mark[2], mark[1]))
      at_line_start = false
    end
  end

  -- Close the current dot line so whatever prints next (a streamed OUTPUT block,
  -- or the final report) starts at column 0 instead of trailing the dots.
  local function newline()
    if not at_line_start then
      write("\n")
      at_line_start = true
    end
  end

  return { on_item = on_item, newline = newline, finish = newline }
end

return M
