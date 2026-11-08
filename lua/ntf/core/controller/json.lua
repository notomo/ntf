local tree = require("ntf.core.tree")
local relative = require("ntf.core.path").relative

local M = {}

--- @class NtfJSONTest one test, as a document spells it
--- @field file string the spec file, relative to the working directory
--- @field row integer? the 1-based line the test was declared on
--- @field names string[] the describe/it name chain
--- @field full_name string the chain joined by spaces, which is what --filter matches

--- @class NtfJSONResult : NtfJSONTest
--- @field status NtfResultStatus
--- @field message string? what a failed or errored test raised
--- @field traceback string? where it raised
--- @field duration number? wall time in seconds
--- @field output string? what the test printed, when it printed anything

--- @class NtfJSONOutput what a worker printed for a test no result answered for
--- @field file string the spec file, relative to the working directory
--- @field name string the full name the worker covered
--- @field output string the captured stdout/stderr blob

--- @param file string a spec file path, plain or as a trace spells it
--- @return string # the same path relative to the working directory
local function rel_path(file)
  return relative((file:gsub("^@", "")), vim.fn.getcwd())
end

--- @param names string[]
--- @param trace NtfTrace?
--- @param file string? the spec file, read where a result carries no trace
--- @return NtfJSONTest
local function test_entry(names, trace, file)
  return {
    file = rel_path((trace and trace.source) or file or ""),
    row = trace and trace.line or nil,
    names = names,
    full_name = tree.full_name(names),
  }
end

--- @param load_errors NtfLoadError[]
--- @return { file: string, message: string }[]
local function load_error_entries(load_errors)
  local entries = {}
  for _, load_error in ipairs(load_errors) do
    table.insert(entries, { file = rel_path(load_error.file), message = load_error.message })
  end
  return entries
end

--- @param items NtfWorkItem[]
--- @param load_errors NtfLoadError[]
--- @return string # one document per listing: the tests it found, and the specs that failed to load
function M.list(items, load_errors)
  local tests = {}
  for _, item in ipairs(items) do
    table.insert(tests, test_entry(item.names, item.trace, item.file))
  end
  return vim.json.encode({ tests = tests, load_errors = load_error_entries(load_errors) }) .. "\n"
end

--- @param results NtfResult[]
--- @param load_errors NtfLoadError[]
--- @param timing NtfRunTiming
--- @param opts { gave_up: NtfRunGiveUp?, outputs: NtfWorkerOutput[]? } the budget a run spent, and what its workers printed
--- @return string # one document per run: its results, what it took, and the output no result answered for
function M.run(results, load_errors, timing, opts)
  local outputs = opts.outputs or {}

  local printed = {}
  for _, out in ipairs(outputs) do
    printed[out.file .. "\0" .. out.name] = out
  end

  local entries = {}
  for _, result in ipairs(results) do
    --- @type NtfJSONResult
    local entry = test_entry(result.names, result.trace, result.file)
    local key = (result.file or "") .. "\0" .. entry.full_name
    local out = printed[key]
    printed[key] = nil
    entry.status = result.status
    entry.message = result.message
    entry.traceback = result.traceback
    entry.duration = result.duration
    entry.output = out and out.output or nil
    table.insert(entries, entry)
  end

  local unmatched = {}
  for _, out in ipairs(outputs) do
    if printed[out.file .. "\0" .. out.name] then
      table.insert(unmatched, { file = rel_path(out.file), name = out.name, output = out.output })
    end
  end

  return vim.json.encode({
    results = entries,
    load_errors = load_error_entries(load_errors),
    timing = timing,
    gave_up = opts.gave_up,
    outputs = next(unmatched) and unmatched or nil,
  }) .. "\n"
end

return M
