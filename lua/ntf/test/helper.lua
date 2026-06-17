-- Test helper for ntf's own specs. ntf self-hosts: its specs run under ntf, so
-- the global `assert` and the busted-style globals are already injected.
local helper = {}

local root = vim.fn.fnamemodify(vim.api.nvim_get_runtime_file("lua/ntf/init.lua", false)[1], ":p:h:h:h")
helper.root = root

local data_dir = require("ntf.vendor.misclib.test.data_dir")
local data_root = vim.fs.joinpath(root, "spec")

function helper.before_each()
  helper.test_data = data_dir.setup(data_root, { base_dir = ("test_data_%d/"):format(vim.fn.getpid()) })
end

function helper.after_each()
  helper.test_data:teardown()
end

--- Write spec source to a temporary file and return its path (for `tree.build`).
--- @param source string
--- @return string path
function helper.write_spec(source)
  return helper.test_data:create_file("temp_spec.lua", source)
end

local is_win = vim.fn.has("win32") == 1
local script = vim.fs.joinpath(root, "bin", is_win and "ntf.bat" or "ntf")

--- Launch the real `bin/ntf` (`bin/ntf.bat` on Windows) as a subprocess and wait
--- for it. This is the end-to-end entry point: it spawns a controller nvim which
--- in turn spawns worker nvims, just like a user running the CLI.
--- @param args string[] CLI arguments (paths and flags)
--- @return { code: integer, stdout: string, stderr: string }
function helper.run_cli(args)
  -- A .bat cannot be spawned directly by libuv; route it through cmd.exe.
  local cmd = is_win and { "cmd.exe", "/c", script } or { script }
  cmd = vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true, cwd = root }):wait(60000)
end

return helper
