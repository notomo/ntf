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

--- @param cwd string any form of the working directory
--- @return string normalized absolute path with no trailing slash
local function normalize_dir(cwd)
  return (vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p")):gsub("/$", ""))
end

--- The test directories to exclude from coverage, derived from where the spec
--- files actually live: each spec file's top-level directory under `cwd`. The
--- test directory is not assumed to be `spec/` — whatever directory the specs
--- were found in is excluded, and so is anything alongside them in it (e.g. the
--- cloned test dependencies the workflow puts under `spec/.shared/packages/...`).
--- @param spec_files string[] absolute paths of the spec files being run
--- @param cwd string working directory (any form)
--- @return string[] absolute dir prefixes (each ending with "/") to exclude
function M.exclude_roots(spec_files, cwd)
  cwd = normalize_dir(cwd)
  local roots = {}
  local seen = {}
  for _, file in ipairs(spec_files) do
    local abs = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))
    if abs:sub(1, #cwd + 1) == cwd .. "/" then
      local first = abs:sub(#cwd + 2):match("^[^/]+")
      -- Only a directory (the spec lives below it) makes a subtree to exclude;
      -- a spec file sitting directly in cwd has no top-level dir of its own.
      if first and abs:sub(#cwd + 2) ~= first then
        local root = cwd .. "/" .. first .. "/"
        if not seen[root] then
          seen[root] = true
          table.insert(roots, root)
        end
      end
    end
  end
  return roots
end

--- Decide, once per distinct chunk source, whether to measure it and under which
--- path. Only production files under `cwd` are measured: any `*_spec.lua` file
--- and anything under one of the `excludes` test-directory roots are skipped. So
--- in a user's project this is their own source (the specs and the other test
--- deps live in the excluded test directory); when ntf self-hosts it is ntf's
--- `lua/`.
--- @param cwd string normalized absolute working directory
--- @param excludes string[] absolute dir prefixes (each ending with "/") to skip
--- @return fun(source: string): string|false
local function make_resolver(cwd, excludes)
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
      local in_test_tree = false
      for _, prefix in ipairs(excludes) do
        if path:sub(1, #prefix) == prefix then
          in_test_tree = true
          break
        end
      end
      if under_cwd and not in_test_tree and not path:match("_spec%.lua$") then
        result = path
      end
    end

    decided[source] = result
    return result
  end
end

--- Start collecting. Installs the line hook; pair with `M.stop`.
--- @param opts { cwd: string, excludes?: string[] }
function M.start(opts)
  local cwd = normalize_dir(opts.cwd)
  local resolve = make_resolver(cwd, opts.excludes or {})
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
