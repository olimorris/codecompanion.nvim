-- File watching logic inspired and adapted from sidekick.nvim
-- https://github.com/folke/sidekick.nvim/blob/main/lua/sidekick/cli/watch.lua

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

M.watches = {} ---@type table<string, uv.uv_fs_event_t>
M.enabled = false

---Debounce a function using a libuv timer
---@generic T
---@param fn T
---@param ms? number
---@return T
local function debounce(fn, ms)
  local timer = assert(uv.new_timer())
  return function(...)
    local args = { ... }
    timer:start(
      ms or 20,
      0,
      vim.schedule_wrap(function()
        pcall(fn, unpack(args))
      end)
    )
  end
end

---Return the parent directory of a buffer's file, or nil if ineligible
---@param buf number
---@return string|nil
local function dirname(buf)
  local fname = api.nvim_buf_get_name(buf)
  if
    api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].buflisted
    and fname ~= ""
    and uv.fs_stat(fname) ~= nil
  then
    local path = vim.fs.dirname(fname)
    return path and path ~= "" and path or nil
  end
end

---Refresh checktime
---@return nil
function M.refresh()
  vim.cmd.checktime()
end

---Start watching a specific directory path
---@param path string
---@return nil
function M.start(path)
  if M.watches[path] then
    return
  end

  local watch = uv.new_fs_event()
  if not watch then
    return log:warn("Could not create file watcher for %s", path)
  end

  local ok, err = watch:start(path, {}, function()
    M.refresh()
  end)
  if not ok then
    log:warn("Failed to watch %s: %s", path, err)
    if not watch:is_closing() then
      watch:close()
    end
    return
  end

  M.watches[path] = watch
  log:debug("File watcher started on %s", path)
end

---Stop watching a specific directory path
---@param path string
---@return nil
function M.stop(path)
  local watch = M.watches[path]
  if not watch then
    return
  end

  M.watches[path] = nil
  if not watch:is_closing() then
    watch:close()
  end
  log:debug("File watcher stopped for %s", path)
end

---Update watches based on currently loaded buffers.
---Starts watches for new buffer directories and stops watches for removed ones.
---@return nil
function M.update()
  local dirs = {} ---@type table<string, boolean>
  for _, buf in pairs(api.nvim_list_bufs()) do
    local dir = dirname(buf)
    if dir then
      dirs[dir] = true
      M.start(dir)
    end
  end
  for path in pairs(M.watches) do
    if not dirs[path] then
      M.stop(path)
    end
  end
end

---Enable file system watching for all loaded buffers
---@return nil
function M.enable()
  local watcher = config.interactions.opts.watcher
  if M.enabled or not watcher.enabled then
    return
  end

  M.enabled = true
  M.refresh = debounce(M.refresh, watcher.debounce)
  M.update = debounce(M.update, watcher.debounce)

  api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout", "BufReadPost" }, {
    group = api.nvim_create_augroup("codecompanion.watch", { clear = true }),
    callback = M.update,
  })
  M.update()
end

---Disable file system watching and stop all active watches
---@return nil
function M.disable()
  if not M.enabled then
    return
  end

  M.enabled = false
  pcall(api.nvim_clear_autocmds, { group = "codecompanion.watch" })
  pcall(api.nvim_del_augroup_by_name, "codecompanion.watch")
  for path in pairs(M.watches) do
    M.stop(path)
  end
end

return M
