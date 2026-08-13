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

--- @param candidates fun(salt: integer): string[] ascending keys, built from a salt so that another call gives them other hashes
--- @return string[] # the first candidate set a table does not already hand back ascending
function helper.unsorted_hash_order(candidates)
  for salt = 1, 100 do
    local ascending = candidates(salt)
    local keyed = {}
    for _, key in ipairs(ascending) do
      keyed[key] = true
    end
    if not vim.deep_equal(ascending, vim.tbl_keys(keyed)) then
      return ascending
    end
  end
  error("every candidate set came back out of a table ascending")
end

local is_win = vim.fn.has("win32") == 1
local script = vim.fs.joinpath(root, "bin", is_win and "ntf.bat" or "ntf")

--- @param path string a file the call reads
--- @param read fun() calls production code that opens `path` for reading, and is called again while the descriptor keeps shifting
--- @return boolean # whether the call left the file open
function helper.leaves_file_open(path, read)
  if is_win then
    read()
    local windows_refuses_to_delete_a_file_a_handle_still_holds = vim.fn.delete(path) ~= 0
    return windows_refuses_to_delete_a_file_a_handle_still_holds
  end

  --- @return integer # the descriptor the next open takes, which one left open shifts
  local function next_descriptor()
    local fd = assert(vim.uv.fs_open(path, "r", tonumber("666", 8)))
    vim.uv.fs_close(fd)
    return fd
  end

  -- WHY: the descriptor an open takes is the lowest the whole process has free,
  -- so anything else in the process moves the number. A worker starts the libuv
  -- loop of its watchdog thread once, and under load that start lands inside the
  -- call being measured, where the epoll and the pipes the loop takes shift the
  -- descriptor exactly as a file left open would. One start cannot reach a
  -- second reading, while a file left open shifts every one.
  -- NOT: taking a single reading, which reports a file the call did close as
  -- left open.
  --- @type integer readings that have to shift before the file counts as left open
  local agreeing_readings = 3

  collectgarbage("stop")
  local left_open = true
  for _ = 1, agreeing_readings do
    local before = next_descriptor()
    read()
    if next_descriptor() == before then
      left_open = false
      break
    end
  end
  collectgarbage("restart")
  return left_open
end

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
