local setup_highlight_groups = function()
  local highlightlib = require("ntf.vendor.misclib.highlight")
  return {
    --- covered lines
    NtfCoverageCovered = highlightlib.link("NtfCoverageCovered", "DiffAdd"),
    --- coverable-but-missed lines
    NtfCoverageMissed = highlightlib.link("NtfCoverageMissed", "DiffDelete"),
  }
end

local group = vim.api.nvim_create_augroup("ntf.coverage.highlight_group", {})
vim.api.nvim_create_autocmd({ "ColorScheme" }, {
  group = group,
  pattern = { "*" },
  callback = function()
    setup_highlight_groups()
  end,
})

return setup_highlight_groups()
