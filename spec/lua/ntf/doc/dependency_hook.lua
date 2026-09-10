-- dependency_hook.lua
return {
  setup = function()
    vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.getcwd(), "deps/dependency"))
    vim.cmd.runtime({ args = { "plugin/**/*.{vim,lua}" }, bang = true })
  end,
}
