---@class CodeCompanion.BufferChange
---@field start_row number The starting row of the change
---@field end_row number The ending row of the change
---@field lines table The changed lines content
---@field changedtick number The buffer change tick when this change occurred
---@field timestamp number The timestamp when the change occurred
---@field reported boolean Whether this change has been reported to the LLM

---@class CodeCompanion.BufferState
---@field changes CodeCompanion.BufferChange[] Array of changes for this buffer
---@field last_changedtick number The last recorded change tick

---@class CodeCompanion.BufferWatcher
---@field buffers table<number, CodeCompanion.BufferState> Map of buffer numbers to their states
---@field watch fun(self: CodeCompanion.BufferWatcher, bufnr: number): nil Start watching a buffer
---@field unwatch fun(self: CodeCompanion.BufferWatcher, bufnr: number): nil Stop watching a buffer
---@field get_changes fun(self: CodeCompanion.BufferWatcher, bufnr: number): CodeCompanion.BufferChange[]|nil Get unreported changes
---@field clear_changes fun(self: CodeCompanion.BufferWatcher, bufnr: number): nil Clear all changes for a buffer
local Watcher = {}
local log = require("codecompanion.utils.log")

function Watcher.new()
  return setmetatable({
    buffers = {},
  }, { __index = Watcher })
end

function Watcher:watch(bufnr)
  if self.buffers[bufnr] then
    return
  end

  log:debug("Starting to watch buffer: %d", bufnr)

  self.buffers[bufnr] = {
    changes = {},
    last_changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
  }

  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, changedtick, start_row, start_col, end_row, end_col, _, _)
      if not self.buffers[buf] then
        return
      end

      -- Get the changed lines
      local lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
      table.insert(self.buffers[buf].changes, {
        start_row = start_row + 1,
        end_row = end_row,
        lines = lines,
        changedtick = changedtick,
        timestamp = vim.loop.now(),
        reported = false,
      })
      log:debug("Recording change in buffer %d: lines %d-%d: %s", buf, start_row + 1, end_row + 1, vim.inspect(lines))
    end,
    on_detach = function(_, buf)
      self.buffers[buf] = nil
      log:debug("Detached from buffer: %d", buf)
    end,
  })
end

function Watcher:unwatch(bufnr)
  if self.buffers[bufnr] then
    vim.api.nvim_buf_attach(bufnr, false, {})
  end
end

function Watcher:get_changes(bufnr)
  if not self.buffers[bufnr] then
    return nil
  end

  -- Get unreported changes
  local unreported = vim.tbl_filter(function(change)
    return not change.reported
  end, self.buffers[bufnr].changes)

  if #unreported == 0 then
    return nil
  end

  -- Sort changes by timestamp and line number
  table.sort(unreported, function(a, b)
    if a.start_row == b.start_row then
      return a.timestamp < b.timestamp
    end
    return a.start_row < b.start_row
  end)

  -- Mark changes as reported
  for _, change in ipairs(unreported) do
    change.reported = true
  end

  log:debug("Found %d unreported changes in buffer %d", #unreported, bufnr)
  return unreported
end

function Watcher:clear_changes(bufnr)
  if self.buffers[bufnr] then
    self.buffers[bufnr].changes = {}
    log:debug("Cleared changes for buffer %d", bufnr)
  end
end

return Watcher
