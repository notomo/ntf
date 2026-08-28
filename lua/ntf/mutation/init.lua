local results = require("ntf.core.mutation.results")
local cache_path = require("ntf.core.cache_path")
local oneline = require("ntf.core.controller.report").oneline
local absolute = require("ntf.core.path").absolute

local M = {}

local ns = vim.api.nvim_create_namespace("ntf.mutation")

local SIGN = "▌"

vim.diagnostic.config({
  signs = { text = { [vim.diagnostic.severity.WARN] = SIGN } },
  virtual_text = false,
  virtual_lines = { current_line = false },
}, ns)

--- @class NtfMutationResultsPathOption
--- @field working_dir string? the directory the run was made from (default:
---   the current one).

--- The results file `ntf mutation` writes for a directory, which is what
--- `decorate` reads when it is given no path. Resolve it yourself to decorate a
--- buffer against a project other than the current directory.
--- @param opts NtfMutationResultsPathOption?: |NtfMutationResultsPathOption|
--- @return string
function M.results_path(opts)
  opts = opts or {}
  return cache_path.mutation_results(opts.working_dir)
end

--- @class NtfMutationDecorateOption
--- @field enable boolean? when `false`, clear the decoration instead of drawing
---   it (default `true`).
--- @field path string? mutation results file to read
---   (default: |ntf.mutation.results_path()|).
--- @field buffer integer? target buffer (default `0`, the current buffer).

--- Mark a buffer's surviving mutants, read from the results file (as
--- written by `ntf mutation`): each mutant a test let through becomes a warning
--- diagnostic in |ntf.mutation.namespace()|, underlining the code it changed
--- and carrying what it put there as its message, `ntf` as its source and the
--- operator as its code — which the virtual-lines handler prefixes to the
--- message and |vim.diagnostic.open_float()| appends to it. What the mutant
--- replaced is the underlined code itself, so the message spells only the
--- replacement, on one line and cut to a width a buffer can carry. Detected
--- mutants are not set: they say nothing about the tests.
--- @param opts NtfMutationDecorateOption?: |NtfMutationDecorateOption|
function M.decorate(opts)
  opts = opts or {}
  local bufnr = opts.buffer or 0
  local enable = opts.enable ~= false

  vim.diagnostic.reset(ns, bufnr)
  if not enable then
    return
  end

  local path = opts.path or M.results_path()
  local data = results.read(path)
  if not data then
    local full_path = absolute(path)
    error(("[ntf] mutation results file is not found: %s"):format(full_path), 0)
  end

  local file = absolute(vim.api.nvim_buf_get_name(bufnr))
  local records = (data.files or {})[file] or {}

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local diagnostics = {}
  for _, record in ipairs(records) do
    if record.status == "survived" and record.row <= line_count then
      table.insert(diagnostics, {
        lnum = record.row - 1,
        col = record.col,
        end_lnum = record.end_row - 1,
        end_col = record.end_col,
        severity = vim.diagnostic.severity.WARN,
        source = "ntf",
        code = record.operator,
        message = oneline(record.replacement),
      })
    end
  end
  vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- @class NtfMutationIsDecoratedOption
--- @field buffer integer? target buffer (default `0`, the current buffer).

--- Whether the buffer holds survivors `decorate` set. Intended for a
--- toggle mapping paired with `decorate`.
--- @param opts NtfMutationIsDecoratedOption?: |NtfMutationIsDecoratedOption|
--- @return boolean
function M.is_decorated(opts)
  opts = opts or {}
  local counts = vim.diagnostic.count(opts.buffer or 0, { namespace = ns })
  return not vim.tbl_isempty(counts)
end

--- The diagnostic namespace `decorate` sets the survivors in. Requiring this
--- module gives the namespace a display of its own — the `▌` sign, and every
--- message under the code it belongs to as virtual lines
--- (|vim.diagnostic.Opts.VirtualLines|), drawn as soon as `decorate` runs and
--- taking a line apiece, so that a second survivor on a line does not run into
--- the first — which `vim.diagnostic.config(opts, ntf.mutation.namespace())`
--- overrides. It is also what `vim.diagnostic.get()`, `jump()` and
--- `setloclist()` take to work with the survivors alone.
--- @return integer
function M.namespace()
  return ns
end

return M
