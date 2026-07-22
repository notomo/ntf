local helper = {}

local root = vim.fn.fnamemodify(vim.api.nvim_get_runtime_file("lua/ntf/init.lua", false)[1], ":p:h:h:h")
helper.root = root

local data_dir = require("ntf.vendor.misclib.test.data_dir")
local data_root = vim.fs.joinpath(root, "spec")

function helper.before_each()
  helper.test_data = data_dir.setup(data_root)
end

function helper.after_each()
  helper.test_data:teardown()
end

--- @param source string
--- @return string path
function helper.write_spec(source)
  return helper.test_data:create_file("temp_spec.lua", source)
end

local is_win = vim.fn.has("win32") == 1
local script = vim.fs.joinpath(root, "bin", is_win and "ntf.bat" or "ntf")

--- @param args string[] CLI arguments (paths and flags)
--- @param cwd string? working directory for the subprocess (default: plugin root)
--- @return { code: integer, stdout: string, stderr: string }
function helper.run_cli(args, cwd)
  local cmd = is_win and { "cmd.exe", "/c", script } or { script }
  cmd = vim.list_extend(cmd, args)
  local env = { XDG_CACHE_HOME = helper.test_data:path("xdg_cache") }
  return vim.system(cmd, { text = true, cwd = cwd or root, env = env }):wait(60000)
end

return helper
