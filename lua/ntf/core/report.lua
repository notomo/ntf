-- Renders aggregated results into a balanced human/agent-readable report (or
-- JSON with --json) and computes the process exit code.
local M = {}

local COLORS = {
  red = "\27[31m",
  green = "\27[32m",
  yellow = "\27[33m",
  dim = "\27[90m",
  bold = "\27[1m",
  reset = "\27[0m",
}

local function painter(enabled)
  return function(color, text)
    if not enabled then
      return text
    end
    return (COLORS[color] or "") .. text .. COLORS.reset
  end
end

local function rel_source(trace)
  if not trace or not trace.source then
    return "?"
  end
  local source = trace.source:gsub("^@", "")
  local cwd = vim.fn.getcwd()
  source = source:gsub("^" .. vim.pesc(cwd) .. "/?", "")
  if trace.line then
    return ("%s:%d"):format(source, trace.line)
  end
  return source
end

local function full_name(result)
  return table.concat(
    vim.tbl_filter(function(s)
      return s ~= nil and s ~= ""
    end, result.names or { result.name }),
    " "
  )
end

-- Drop ntf's own runner frames and the [C] error/xpcall noise so the traceback
-- points at the spec code.
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
  -- if nothing but the header remains, it adds no value
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

--- @param results table[]
--- @param load_errors table[]
--- @param opts table { color, json, slow, shuffle, seed }
--- @return string text, integer exit_code
function M.build(results, load_errors, opts)
  load_errors = load_errors or {}

  if opts.json then
    local payload = {
      results = results,
      load_errors = load_errors,
      seed = opts.shuffle and opts.seed or nil,
    }
    local code = #load_errors > 0 and 1 or 0
    for _, result in ipairs(results) do
      if result.status == "failed" or result.status == "error" then
        code = 1
      end
    end
    return vim.json.encode(payload), code
  end

  local color
  if opts.color == nil then
    local ok, handle = pcall(function()
      return vim.uv.guess_handle(1)
    end)
    color = ok and handle == "tty" and not vim.env.NO_COLOR
  else
    color = opts.color
  end
  local paint = painter(color)

  local counts = { passed = 0, failed = 0, error = 0, pending = 0 }
  local problems = {}
  local slows = {}

  for _, result in ipairs(results) do
    counts[result.status] = (counts[result.status] or 0) + 1
    if result.status == "failed" or result.status == "error" then
      table.insert(problems, result)
    end
    if opts.slow and result.duration and result.duration * 1000 >= opts.slow then
      table.insert(slows, result)
    end
  end

  local lines = {}

  for _, load_error in ipairs(load_errors) do
    local rel = load_error.file:gsub("^" .. vim.pesc(vim.fn.getcwd()) .. "/?", "")
    table.insert(lines, paint("red", "LOAD ERROR ") .. rel)
    table.insert(lines, indent(load_error.message, "    "))
    table.insert(lines, "")
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

  if #slows > 0 then
    table.sort(slows, function(a, b)
      return (a.duration or 0) > (b.duration or 0)
    end)
    table.insert(lines, paint("yellow", ("Slow (>= %d ms):"):format(opts.slow)))
    for _, result in ipairs(slows) do
      table.insert(lines, ("  %.1f ms  %s"):format(result.duration * 1000, full_name(result)))
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
  if opts.shuffle and opts.seed then
    table.insert(lines, paint("dim", "seed: " .. tostring(opts.seed)))
  end

  local code = (counts.failed > 0 or counts.error > 0 or #load_errors > 0) and 1 or 0
  return table.concat(lines, "\n") .. "\n", code
end

return M
