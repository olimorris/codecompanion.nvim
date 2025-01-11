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

  -- Special case: empty buffer getting content
  -- NOTE: An "empty" buffer in Neovim actually contains one empty line ("")
  if (old_size == 0 or (old_size == 1 and old_lines[1] == "")) and new_size > 0 then
    return {
      {
        type = "add",
        start = 1,
        end_line = new_size,
        lines = new_lines,
      },
    }
  end

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

  --TODO: maybe we can ensure there are changes before doing this, like :
  -- start_diff <= math.min(old_size, new_size) or old_size ~= new_size
  -- need more testing.
  if start_diff > math.min(old_size, new_size) and old_size == new_size then
    return changes
  end

  -- Compare lines within the differing range to separate modifications from deletions/additions
  local i = start_diff
  local j = start_diff

  while i <= old_end and j <= new_end do
    if old_lines[i] ~= new_lines[j] then
      -- If we have lines on both sides, it's a modification
      if i <= old_end and j <= new_end then
        table.insert(changes, {
          type = "modify",
          start = i,
          end_line = i,
          old_lines = { old_lines[i] },
          new_lines = { new_lines[j] },
        })
      end
    end
    i = i + 1
    j = j + 1
  end

  -- Handle remaining deletions
  if i <= old_end then
    local deleted = {}
    for k = i, old_end do
      table.insert(deleted, old_lines[k])
    end
    table.insert(changes, {
      type = "delete",
      start = i,
      end_line = old_end,
      lines = deleted,
    })
  end

  -- Handle remaining additions
  if j <= new_end then
    local added = {}
    for k = j, new_end do
      table.insert(added, new_lines[k])
    end
    table.insert(changes, {
      type = "add",
      start = j,
      end_line = new_end,
      lines = added,
    })
  end

  return changes
end

function Watcher:get_changes(bufnr)
  if not self.buffers[bufnr] then
    return nil
  end

  -- Check if buffer still exists
  if not vim.api.nvim_buf_is_valid(bufnr) then
    -- Buffer was deleted, clean up our state
    self.buffers[bufnr] = nil
    return nil
  end

  local buffer = self.buffers[bufnr]
  local current_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- TODO: we can compare buffer content to be more robus as well, maybe using
  -- vim.deep_equal
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
