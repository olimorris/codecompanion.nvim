---@class CodeCompanion.BufferState
---@field content table Complete buffer content
---@field changedtick number Last known changedtick

local Watcher = {}
local log = require("codecompanion.utils.log")

function Watcher.new()
  return setmetatable({
    buffers = {},
    augroup = vim.api.nvim_create_augroup("CodeCompanionWatcher", { clear = true }),
  }, { __index = Watcher })
end

function Watcher:watch(bufnr)
  if self.buffers[bufnr] then
    return
  end

  log:debug("Starting to watch buffer: %d", bufnr)

  -- Store initial buffer state
  self.buffers[bufnr] = {
    content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
  }
end

function Watcher:unwatch(bufnr)
  if self.buffers[bufnr] then
    log:debug("Unwatching buffer %d", bufnr)
    self.buffers[bufnr] = nil
  end
end

---Compare two arrays of lines and return their differences
---@param old_lines table
---@param new_lines table
---@return table changes
local function compare_contents(old_lines, new_lines)
  local changes = {}
  local old_size = #old_lines
  local new_size = #new_lines

  -- Find first different line
  local start_diff = 1
  while start_diff <= math.min(old_size, new_size) do
    if old_lines[start_diff] ~= new_lines[start_diff] then
      break
    end
    start_diff = start_diff + 1
  end

  -- Find last different line from the end
  local old_end = old_size
  local new_end = new_size
  while old_end >= start_diff and new_end >= start_diff do
    if old_lines[old_end] ~= new_lines[new_end] then
      break
    end
    old_end = old_end - 1
    new_end = new_end - 1
  end

  -- Extract deleted lines
  if old_end >= start_diff then
    local deleted = {}
    for i = start_diff, old_end do
      table.insert(deleted, old_lines[i])
    end
    if #deleted > 0 then
      table.insert(changes, {
        type = "delete",
        start = start_diff,
        end_line = old_end,
        lines = deleted,
      })
    end
  end

  -- Extract added/modified lines
  if new_end >= start_diff then
    local added = {}
    for i = start_diff, new_end do
      table.insert(added, new_lines[i])
    end
    if #added > 0 then
      table.insert(changes, {
        type = "add",
        start = start_diff,
        end_line = new_end,
        lines = added,
      })
    end
  end

  return changes
end

function Watcher:get_changes(bufnr)
  if not self.buffers[bufnr] then
    return nil
  end

  local buffer = self.buffers[bufnr]
  local current_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- If no changes, return nil
  if current_tick == buffer.changedtick then
    return nil
  end

  -- Compare old and new content
  local changes = compare_contents(buffer.content, current_content)

  -- Update stored state
  buffer.content = current_content
  buffer.changedtick = current_tick

  return changes
end

return Watcher
