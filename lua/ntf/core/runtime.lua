local M = {}

function M.setup()
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
end

return M
