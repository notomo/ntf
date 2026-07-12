-- Streamed to stderr as workers complete, so a long (or hung) run shows it is
-- alive. Plain dots, no in-place `\r` redraw, so the stream survives non-tty
-- capture (agents, CI) too.
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

  local function newline()
    if not at_line_start then
      write("\n")
      at_line_start = true
    end
  end

  return { on_item = on_item, newline = newline, finish = newline }
end

--- @type table<string, { [1]: string, [2]: ("red"|"yellow")? }> mutant status -> mark char and color
local MUTANT_MARKS = {
  killed = { "." },
  timeout = { "T" },
  survived = { "S", "red" },
  not_applied = { "?", "yellow" },
}

--- The mutation run takes the same shape: one character per mutant, streamed as
--- it settles.
--- @param opts { write: fun(text: string), enabled: boolean, color: boolean }
--- @return { on_start: fun(total: integer), on_task: fun(outcome: NtfMutantOutcome), finish: fun() }
function M.mutation(opts)
  if not opts.enabled then
    return { on_start = function() end, on_task = function() end, finish = function() end }
  end

  local function paint(name, text)
    if not opts.color or not name then
      return text
    end
    return COLORS[name] .. text .. COLORS.reset
  end

  local function on_start(total)
    opts.write(("mutants (%d): "):format(total))
  end

  local function on_task(outcome)
    local mark = MUTANT_MARKS[outcome.status] or MUTANT_MARKS.survived
    opts.write(paint(mark[2], mark[1]))
  end

  local function finish()
    opts.write("\n")
  end

  return { on_start = on_start, on_task = on_task, finish = finish }
end

return M
