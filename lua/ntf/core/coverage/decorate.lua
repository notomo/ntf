local stats = require("ntf.core.coverage.stats")
local coverage_lines = require("ntf.core.coverage.lines")
local highlight_group = require("ntf.core.coverage.highlight_group")

local M = {}

local ns = vim.api.nvim_create_namespace("ntf.coverage")

local SIGN = "▌"

--- @param opts { enable: boolean?, path: string?, buffer: integer? }?
function M.decorate(opts)
  opts = opts or {}
  local bufnr = opts.buffer or 0
  local enable = opts.enable ~= false

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not enable then
    return
  end

  local path = opts.path or "./luacov.stats.out"
  if not vim.uv.fs_stat(path) then
    local full_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    error(("[ntf] coverage file is not found: %s"):format(full_path), 0)
  end

  local data = stats.read(path)
  local file = vim.fs.normalize(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"))
  local entry = data[file]
  if not entry then
    return
  end

  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local coverable = coverage_lines.coverable(table.concat(buf_lines, "\n"))
  for i, _ in ipairs(buf_lines) do
    local hits = entry.lines[i]
    local hl
    if hits and hits > 0 then
      hl = highlight_group.NtfCoverageCovered
    elseif coverable[i] then
      hl = highlight_group.NtfCoverageMissed
    end
    if hl then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
        sign_text = SIGN,
        sign_hl_group = hl,
      })
    end
  end
end

--- @param opts { buffer: integer? }?
--- @return boolean
function M.is_decorated(opts)
  opts = opts or {}
  local marks = vim.api.nvim_buf_get_extmarks(opts.buffer or 0, ns, 0, -1, { limit = 1 })
  return #marks > 0
end

return M
