local tree = require("ntf.core.tree")
local relative = require("ntf.core.path").relative

local M = {}

local COLORS = {
  red = "\27[31m",
  green = "\27[32m",
  yellow = "\27[33m",
  dim = "\27[90m",
  bold = "\27[1m",
  reset = "\27[0m",
}

--- @param enabled boolean
--- @return fun(color: string, text: string): string
function M.painter(enabled)
  return function(color, text)
    if not enabled then
      return text
    end
    return (COLORS[color] or "") .. text .. COLORS.reset
  end
end
local painter = M.painter

--- @param trace NtfTrace?
--- @return string # cwd-relative "path:line"
function M.rel_source(trace)
  if not trace or not trace.source then
    return "?"
  end
  local source = relative((trace.source:gsub("^@", "")), vim.fn.getcwd())
  if trace.line then
    return ("%s:%d"):format(source, trace.line)
  end
  return source
end
local rel_source = M.rel_source

local function full_name(result)
  return tree.full_name(result.names or { result.name })
end

local function clean_traceback(traceback)
  local kept = {}
  for _, line in ipairs(vim.split(traceback or "", "\n", { plain = true })) do
    local drop = line:find("/lua/ntf/", 1, true)
      or line:find("in function 'xpcall'", 1, true)
      or line:find("in function 'error'", 1, true)
    if not drop then
      table.insert(kept, line)
    end
  end
  if #kept <= 1 then
    return nil
  end
  return table.concat(kept, "\n")
end

local function indent(text, prefix)
  local lines = vim.split(text or "", "\n", { plain = true })
  return table.concat(
    vim.tbl_map(function(line)
      return prefix .. line
    end, lines),
    "\n"
  )
end

--- @param load_error NtfLoadError
--- @param paint fun(color: string, text: string): string
--- @return string[] # lines ending with a blank separator
function M.load_error_block(load_error, paint)
  local rel = relative(load_error.file, vim.fn.getcwd())
  return {
    paint("red", "LOAD ERROR ") .. rel,
    indent(load_error.message, "    "),
    "",
  }
end

--- @return boolean
function M.resolve_color()
  local ok, handle = pcall(function()
    return vim.uv.guess_handle(1)
  end)
  return (ok and handle == "tty" and not vim.env.NO_COLOR) or false
end

--- @param out NtfWorkerOutput
--- @param color boolean
--- @return string
function M.output_block(out, color)
  local paint = painter(color)
  local rel = relative(out.file, vim.uv.cwd() --[[@as string]])
  local lines = {}
  local header = paint("dim", "OUTPUT ") .. paint("dim", rel)
  if out.name and out.name ~= "" then
    header = header .. " " .. paint("bold", out.name)
  end
  table.insert(lines, header)
  table.insert(lines, (out.output:gsub("\n$", "")))
  table.insert(lines, "")
  return table.concat(lines, "\n") .. "\n"
end

--- @type integer characters of a mutant's own source a listed line keeps
local TEXT_LIMIT = 60

-- WHY: a mutant whose node is a whole statement — every drop-call and
-- drop-assignment, and a force-branch or force-loop over a wrapped condition or
-- clause — carries the source's own newlines, which would spread one mutant over
-- as many lines as it spans and leave a list unreadable by line.
-- NOT: taking only the head of the node, which every operator would have to name
-- a different part of; the text is here to recognize the mutant by, and the
-- position in front of it is where it is read in full.
--- @param text string a mutant's original or replacement, as the source spells it
--- @return string # the same text on one line, cut to a width the position in front of it stays readable at
function M.oneline(text)
  local single = (text:gsub("%s+", " "))
  if vim.fn.strchars(single) <= TEXT_LIMIT then
    return single
  end
  return vim.fn.strcharpart(single, 0, TEXT_LIMIT - 1) .. "…"
end

--- @param relative_path string working-directory-relative path of the mutated file
--- @param mutant { row: integer, col: integer, operator: string } col 0-based, as every site counts it
--- @return string # the name every listing prints a mutant under, which is also what `--mutant` spells: its column 1-based, like the one an errorformat reads
function M.locator(relative_path, mutant)
  return ("%s:%d:%d:%s"):format(relative_path, mutant.row, mutant.col + 1, mutant.operator)
end

--- @param seconds number
--- @return string # ms below a second, where one decimal of seconds is all zeroes
function M.duration(seconds)
  if seconds < 1 then
    return ("%.0fms"):format(seconds * 1000)
  end
  return ("%.1fs"):format(seconds)
end
local duration = M.duration

--- @param results NtfResult[]
--- @param timing NtfRunTiming
--- @return string
function M.timing(results, timing)
  local lines = { ("Time: %s elapsed, %d jobs"):format(duration(timing.elapsed), timing.jobs) }

  local test_seconds = 0
  for _, result in ipairs(results) do
    test_seconds = test_seconds + (result.duration or 0)
  end

  if #results > 0 then
    local startup_seconds = (timing.worker - test_seconds) / #results
    table.insert(lines, ("  nvim startup: %s avg per test"):format(duration(startup_seconds)))
    table.insert(lines, ("  test execution: %s total"):format(duration(test_seconds)))
  end

  return table.concat(lines, "\n") .. "\n"
end

--- @param results NtfResult[]
--- @param load_errors NtfLoadError[]
--- @param opts { color: boolean }
--- @return string text, integer exit_code
function M.build(results, load_errors, opts)
  load_errors = load_errors or {}

  local paint = painter(opts.color)

  local counts = { passed = 0, failed = 0, error = 0, pending = 0 }
  local problems = {}

  for _, result in ipairs(results) do
    counts[result.status] = (counts[result.status] or 0) + 1
    if result.status == "failed" or result.status == "error" then
      table.insert(problems, result)
    end
  end

  local lines = {}

  for _, load_error in ipairs(load_errors) do
    vim.list_extend(lines, M.load_error_block(load_error, paint))
  end

  for _, result in ipairs(problems) do
    local label = result.status == "failed" and paint("red", "FAIL") or paint("red", "ERROR")
    table.insert(lines, ("%s %s"):format(label, paint("bold", full_name(result))))
    table.insert(lines, "  " .. paint("dim", rel_source(result.trace)))
    if result.message then
      table.insert(lines, indent(result.message, "    "))
    end
    local traceback = clean_traceback(result.traceback)
    if traceback then
      table.insert(lines, paint("dim", indent(traceback:gsub("^\n", ""), "    ")))
    end
    table.insert(lines, "")
  end

  local total = counts.passed + counts.failed + counts.error + counts.pending
  local parts = {
    paint("green", ("%d passed"):format(counts.passed)),
  }
  if counts.failed > 0 then
    table.insert(parts, paint("red", ("%d failed"):format(counts.failed)))
  end
  if counts.error > 0 then
    table.insert(parts, paint("red", ("%d errors"):format(counts.error)))
  end
  if counts.pending > 0 then
    table.insert(parts, paint("yellow", ("%d pending"):format(counts.pending)))
  end
  table.insert(lines, ("%d tests: %s"):format(total, table.concat(parts, "  ")))

  local code = (counts.failed > 0 or counts.error > 0 or #load_errors > 0) and 1 or 0
  return table.concat(lines, "\n") .. "\n", code
end

return M
