local splice = require("ntf.core.mutation.splice")
local absolute = require("ntf.core.path").absolute

local M = {}

--- @param path string normalized absolute file path
--- @param cwd string normalized absolute working directory
--- @return table<string, true> # the `require` names that resolve to path
function M.module_names(path, cwd)
  local names = {}

  if path:sub(1, #cwd + 1) ~= cwd .. "/" then
    return names
  end
  local relative = path:sub(#cwd + 2)

  local stem = relative:match("^lua/(.*)%.lua$") or relative:match("^(.*)%.lua$")
  if not stem then
    return names
  end

  local name = (stem:gsub("/", "."))
  names[name] = true
  local without_init = name:match("^(.*)%.init$")
  if without_init then
    names[without_init] = true
  end

  return names
end

--- @param mutation NtfWorkerMutation
--- @param cwd string working directory (any form)
--- @return fun(): boolean # whether the mutated source was loaded
--- @return fun() # takes the loader back out and gives the module names back what held them
function M.install(mutation, cwd)
  local normalized_cwd = absolute(cwd)
  local names = M.module_names(mutation.path, normalized_cwd)
  local applied = false

  local function loader(name)
    if not names[name] then
      return nil
    end

    local file = io.open(mutation.path, "r")
    if not file then
      return nil
    end
    local src = file:read("*a")
    file:close()

    local mutated = splice.apply(src, mutation)
    if not mutated then
      return nil
    end

    local chunk, err = loadstring(mutated, "@" .. mutation.path)
    if not chunk then
      return err
    end

    applied = true
    return chunk
  end

  table.insert(package.loaders, 2, loader)

  -- WHY: a module already in package.loaded never reaches a loader, and
  -- something has usually loaded it before the spec does (a test hook, or, as
  -- ntf runs its own specs, ntf itself). Dropping the entry makes the spec's
  -- `require` load the mutated source, while whoever already holds the original
  -- keeps it, so ntf's own machinery is not mutated out from under itself.
  -- NOT: clearing all of `package.loaded`, which would hand ntf's machinery the
  -- mutant too.
  local evicted = {}
  for name in pairs(names) do
    evicted[name] = package.loaded[name]
    package.loaded[name] = nil
  end

  -- WHY: a worker takes one mutant after another, and the names it evicts are
  -- the ones ntf's own machinery is reached by when it mutates itself, so a
  -- mutant left in package.loaded is served to every later `require` of it.
  -- NOT: leaving the eviction to the next mutant's install, which drops the
  -- mutated entry without ever putting the original back.
  local function uninstall()
    for index, installed in ipairs(package.loaders) do
      if installed == loader then
        table.remove(package.loaders, index)
        break
      end
    end
    for name in pairs(names) do
      package.loaded[name] = evicted[name]
    end
  end

  return function()
    return applied
  end, uninstall
end

return M
