local absolute = require("ntf.core.path").absolute

local M = {}

--- @class NtfLoadedFiles what one process loaded of a project's files, from the moment it was started
--- @field paths fun(): string[] every one so far, normalized absolute and sorted
--- @field stop fun() takes the recording out again, for a process that goes on

--- @param name string a module name
--- @return string? # the file Neovim's own loader reads it from, nil for one in no `lua/` directory of the runtimepath
function M.runtime_file(name)
  local relative = (name:gsub("%.", "/"))
  for _, pattern in ipairs({ ("lua/%s.lua"):format(relative), ("lua/%s/init.lua"):format(relative) }) do
    local found = vim.api.nvim_get_runtime_file(pattern, false)[1]
    if found then
      return found
    end
  end
  return nil
end

--- @param cwd string the project's working directory (any form)
--- @return NtfLoadedFiles
function M.start(cwd)
  local root = absolute(cwd)
  --- @type string[] the project's files reached so far, each once
  local reached = {}
  --- @type table<string, true>
  local seen = {}

  --- @param path string a file a load reached, in any form
  local function record(path)
    local normalized = absolute(path)
    if seen[normalized] or normalized:sub(1, #root + 1) ~= root .. "/" then
      return
    end
    seen[normalized] = true
    table.insert(reached, normalized)
  end

  --- @type function the first `package.loaders` entry, which resolves a module the way Neovim's loader and Lua's own do and claims none: Lua's reads its file with C's loadfile, which no replaced global reaches
  local searcher = function(name)
    local path = M.runtime_file(name) or package.searchpath(name, package.path)
    if path then
      record(path)
    end
    return nil
  end
  table.insert(package.loaders, 1, searcher)

  local previous = { loadfile = loadfile, dofile = dofile }
  --- @diagnostic disable-next-line: duplicate-set-field
  _G.loadfile = function(path, ...)
    if path then
      record(path)
    end
    return previous.loadfile(path, ...)
  end
  --- @diagnostic disable-next-line: duplicate-set-field
  _G.dofile = function(path)
    if path then
      record(path)
    end
    return previous.dofile(path)
  end

  return {
    paths = function()
      local paths = vim.list_slice(reached)
      table.sort(paths)
      return paths
    end,
    stop = function()
      for index, loader in ipairs(package.loaders) do
        if loader == searcher then
          table.remove(package.loaders, index)
          break
        end
      end
      _G.loadfile = previous.loadfile
      _G.dofile = previous.dofile
    end,
  }
end

return M
