local results = require("ntf.core.mutation.results")
local highlight_group = require("ntf.mutation.highlight_group")

local M = {}

local ns = vim.api.nvim_create_namespace("ntf.mutation")

local SIGN = "▌"

--- @class NtfMutationDecorateOption
--- @field enable boolean? when `false`, clear the decoration instead of drawing
---   it (default `true`).
--- @field path string? mutation results file to read (default
---   `"./ntf-mutation.json"`).
--- @field buffer integer? target buffer (default `0`, the current buffer).

--- Mark a buffer's surviving mutants, read from an `ntf-mutation.json` (as
--- written by `ntf --mutation`): each line a mutant got away with is signed with
--- the `NtfMutationSurvived` highlight and shows the change it survived as
--- virtual text. Detected mutants are not drawn: they say nothing about the tests.
--- @param opts NtfMutationDecorateOption?: |NtfMutationDecorateOption|
function M.decorate(opts)
  opts = opts or {}
  local bufnr = opts.buffer or 0
  local enable = opts.enable ~= false

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not enable then
    return
  end

  local path = opts.path or "./ntf-mutation.json"
  local data = results.read(path)
  if not data then
    local full_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    error(("[ntf] mutation results file is not found: %s"):format(full_path), 0)
  end

  local file = vim.fs.normalize(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"))
  local records = (data.files or {})[file]
  if not records then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, record in ipairs(records) do
    -- WHY: the buffer may have shrunk since the run that recorded these rows.
    -- NOT: letting `nvim_buf_set_extmark` raise on the out-of-range row.
    if record.status == "survived" and record.row <= line_count then
      vim.api.nvim_buf_set_extmark(bufnr, ns, record.row - 1, 0, {
        sign_text = SIGN,
        sign_hl_group = highlight_group.NtfMutationSurvived,
        virt_text = {
          {
            (" %s: %s -> %s"):format(record.operator, record.original, record.replacement),
            highlight_group.NtfMutationSurvived,
          },
        },
        virt_text_pos = "eol",
      })
    end
  end
end

--- @class NtfMutationIsDecoratedOption
--- @field buffer integer? target buffer (default `0`, the current buffer).

--- Whether `decorate` is currently drawing on the buffer. Intended for a
--- toggle mapping paired with `decorate`.
--- @param opts NtfMutationIsDecoratedOption?: |NtfMutationIsDecoratedOption|
--- @return boolean
function M.is_decorated(opts)
  opts = opts or {}
  local marks = vim.api.nvim_buf_get_extmarks(opts.buffer or 0, ns, 0, -1, { limit = 1 })
  return #marks > 0
end

return M
