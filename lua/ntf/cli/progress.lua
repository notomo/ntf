-- Streaming progress for the controller: one character per finished test,
-- written to stderr as workers complete, so a long (or hung) run shows it is
-- alive instead of staying silent until the final report. Newline based on
-- purpose, so it survives non-tty capture (agents, CI) rather than relying on
-- in-place `\r` updates that only help a live terminal.
local M = {}

local COLORS = {
  red = "\27[31m",
  yellow = "\27[33m",
  reset = "\27[0m",
}

-- status -> { char, color }
local MARKS = {
  passed = { "." },
  failed = { "F", "red" },
  error = { "E", "red" },
  pending = { "*", "yellow" },
}

--- @param opts table { write: fun(string), color: boolean, total: integer, width: integer|nil }
--- @return table { on_item: fun(item, results), finish: fun() }
function M.new(opts)
  local write = opts.write
  local color = opts.color
  local total = opts.total
  local width = opts.width or 50

  local done = 0
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
      done = done + 1
      if done % width == 0 then
        write((" %d/%d\n"):format(done, total))
        at_line_start = true
      end
    end
  end

  -- Close the dot line so the final stdout report starts at column 0.
  local function finish()
    if done > 0 and not at_line_start then
      write("\n")
      at_line_start = true
    end
  end

  return { on_item = on_item, finish = finish }
end

return M
