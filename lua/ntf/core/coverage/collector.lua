-- Line-coverage collector. Runs inside a worker process: installs a Lua line
-- hook that counts how many times each line of the code under test executes.
--
-- Neovim is LuaJIT, where the JIT compiler does not fire line hooks on compiled
-- traces, so coverage would silently under-count. `jit.off()` forces the
-- interpreter for the whole worker, which is why collection only happens under
-- `--coverage` (it makes the worker slower).
local M = {}

-- The accumulator for the currently running collection, or nil when inactive.
-- Shape: { [abs_path] = { max = integer, lines = { [line] = hits } } }.
local active

--- Decide, once per distinct chunk source, whether to measure it and under which
--- path. Only files under `cwd` that are not specs are measured: in a user's
--- project that is their own source (ntf itself lives elsewhere); when ntf
--- self-hosts it is ntf's `lua/` (the `*_spec.lua` files are excluded).
--- @param cwd string normalized absolute working directory
--- @return fun(source: string): string|false
local function make_resolver(cwd)
  local decided = {}
  return function(source)
    local cached = decided[source]
    if cached ~= nil then
      return cached
    end

    --- @type string|false
    local result = false
    -- File chunks are named "@<path>"; anything else (strings, C) is skipped.
    local path = source:match("^@(.*)$")
    if path then
      path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
      local under_cwd = path == cwd or path:sub(1, #cwd + 1) == cwd .. "/"
      if under_cwd and not path:match("_spec%.lua$") then
        result = path
      end
    end

    decided[source] = result
    return result
  end
end

--- Start collecting. Installs the line hook; pair with `M.stop`.
--- @param opts { cwd: string }
function M.start(opts)
  local cwd = vim.fs.normalize(vim.fn.fnamemodify(opts.cwd, ":p")):gsub("/$", "")
  local resolve = make_resolver(cwd)
  local data = {}

  -- A line hook is called as hook("line", linenumber); the source of the
  -- triggering function comes from getinfo at level 2 (the hooked function).
  local function hook(_, line)
    local info = debug.getinfo(2, "S")
    local path = resolve(info.source)
    if not path or line < 1 then
      return
    end
    local entry = data[path]
    if not entry then
      entry = { max = 0, lines = {} }
      data[path] = entry
    end
    -- Line numbers are kept as string keys so the per-file table is a JSON
    -- object: `vim.json.encode` rejects the sparse integer-keyed array this
    -- would otherwise be when serialising the worker's payload.
    local key = tostring(line)
    entry.lines[key] = (entry.lines[key] or 0) + 1
    if line > entry.max then
      entry.max = line
    end
  end

  require("jit").off()
  debug.sethook(hook, "l")
  active = data
end

--- Stop collecting and return the per-file hit counts gathered since `M.start`.
--- @return table<string, { max: integer, lines: table<integer, integer> }>
function M.stop()
  debug.sethook()
  local data = active or {}
  active = nil
  return data
end

--- Merge a worker's per-file counts into an accumulator (summing hits per line).
--- Tolerates string line keys, since the counts arrive JSON-decoded from a
--- worker (`vim.json` turns the integer keys into strings on the way back).
--- @param into table accumulator (same shape as `M.stop`'s return)
--- @param part table|nil one worker's counts
function M.merge(into, part)
  for path, entry in pairs(part or {}) do
    local target = into[path]
    if not target then
      target = { max = 0, lines = {} }
      into[path] = target
    end
    for line, hits in pairs(entry.lines or {}) do
      local n = tonumber(line)
      if n then
        target.lines[n] = (target.lines[n] or 0) + hits
      end
    end
    target.max = math.max(target.max, tonumber(entry.max) or 0)
  end
end

return M
