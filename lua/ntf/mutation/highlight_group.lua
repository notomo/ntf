local setup_highlight_groups = function()
  local highlightlib = require("ntf.vendor.misclib.highlight")
  return {
    -- lines with a mutant no test detected
    NtfMutationSurvived = highlightlib.link("NtfMutationSurvived", "WarningMsg"),
  }
end

local group = vim.api.nvim_create_augroup("ntf.mutation.highlight_group", {})
vim.api.nvim_create_autocmd({ "ColorScheme" }, {
  group = group,
  pattern = { "*" },
  callback = function()
    setup_highlight_groups()
  end,
})

return setup_highlight_groups()
