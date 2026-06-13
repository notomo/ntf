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

return helper
