-- Decorates a buffer's sign column with per-line coverage read from a
-- `luacov.stats.out` file: covered lines vs coverable-but-missed lines. This is
-- the only part of ntf that touches Neovim buffers; it runs in an interactive
-- session, not in a test worker.
local stats = require("ntf.core.coverage.stats")
local source = require("ntf.core.coverage.source")

local M = {}

local ns = vim.api.nvim_create_namespace("ntf.coverage")

local SIGN = "▌"

--- @param opts { enable: boolean?, path: string?, buffer: integer? }?
function M.decorate(opts)
  opts = opts or {}
  local bufnr = opts.buffer or 0
  local enable = opts.enable ~= false

  -- Always clear first so a re-run (or the off path) starts from a clean buffer.
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not enable then
    return
  end

  -- Default, user-overridable highlight groups.
  vim.api.nvim_set_hl(0, "NtfCoverageCovered", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "NtfCoverageMissed", { default = true, link = "DiffDelete" })

  local data = stats.read(opts.path or "./luacov.stats.out")
  local file = vim.fs.normalize(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"))
  local entry = data[file]
  if not entry then
    return
  end

  -- Iterate over the buffer (not the stats file) so a stale stats file can never
  -- place a sign past the buffer's end.
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, text in ipairs(buf_lines) do
    local hits = entry.lines[i]
    local hl
    if hits and hits > 0 then
      hl = "NtfCoverageCovered"
    elseif source.is_code(text) then
      hl = "NtfCoverageMissed"
    end
    if hl then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
        sign_text = SIGN,
        sign_hl_group = hl,
      })
    end
  end
end

--- Whether the buffer currently carries coverage decoration.
--- @param opts { buffer: integer? }?
--- @return boolean
function M.is_decorated(opts)
  opts = opts or {}
  -- We only need to know if any coverage extmark exists, so stop at the first.
  local marks = vim.api.nvim_buf_get_extmarks(opts.buffer or 0, ns, 0, -1, { limit = 1 })
  return #marks > 0
end

return M
