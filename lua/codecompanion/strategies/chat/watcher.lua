---@class CodeCompanion.BufferState
---@field content table Complete buffer content
---@field changedtick number Last known changedtick
---@field last_sent table Last content sent to LLM

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

  if not vim.api.nvim_buf_is_valid(bufnr) then
    log:debug("Cannot watch invalid buffer: %d", bufnr)
    return
  end

  log:debug("Starting to watch buffer: %d", bufnr)
  local initial_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  self.buffers[bufnr] = {
    content = initial_content,
    last_sent = initial_content,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
  }

  vim.api.nvim_create_autocmd("BufDelete", {
    group = self.augroup,
    buffer = bufnr,
    callback = function()
      self:unwatch(bufnr)
    end,
  })
end

function Watcher:unwatch(bufnr)
  if self.buffers[bufnr] then
    log:debug("Unwatching buffer %d", bufnr)
    self.buffers[bufnr] = nil
  end
end

local function find_line_match(line, lines, start_idx)
  for i = start_idx or 1, #lines do
    if lines[i] == line then
      return i
    end
  end
  return nil
end

local function detect_changes(old_lines, new_lines)
  local changes = {}
  local old_size = #old_lines
  local new_size = #new_lines

  local i = 1 -- old lines index
  local j = 1 -- new lines index

  while i <= old_size or j <= new_size do
    if i > old_size then
      -- Remaining lines are new additions
      local added = {}
      local start = j
      while j <= new_size do
        table.insert(added, new_lines[j])
        j = j + 1
      end
      if #added > 0 then
        table.insert(changes, {
          type = "add",
          start = start,
          end_line = new_size,
          lines = added,
        })
      end
      break
    end

    if j > new_size then
      -- Remaining lines are deletions
      local deleted = {}
      local start = i
      while i <= old_size do
        table.insert(deleted, old_lines[i])
        i = i + 1
      end
      if #deleted > 0 then
        table.insert(changes, {
          type = "delete",
          start = start,
          end_line = old_size,
          lines = deleted,
        })
      end
      break
    end

    if old_lines[i] == new_lines[j] then
      -- Lines match, move both forward
      i = i + 1
      j = j + 1
    else
      -- Look ahead for matches
      local next_match = find_line_match(old_lines[i], new_lines, j)
      if next_match then
        -- Found the line later - everything before is new
        local added = {}
        local start = j
        while j < next_match do
          table.insert(added, new_lines[j])
          j = j + 1
        end
        if #added > 0 then
          table.insert(changes, {
            type = "add",
            start = start,
            end_line = next_match - 1,
            lines = added,
          })
        end
      else
        -- Line was deleted or modified
        local next_old_match = find_line_match(new_lines[j], old_lines, i)
        if next_old_match then
          -- Found matching line later in old content - report deletions
          local deleted = {}
          local start = i
          while i < next_old_match do
            table.insert(deleted, old_lines[i])
            i = i + 1
          end
          if #deleted > 0 then
            table.insert(changes, {
              type = "delete",
              start = start,
              end_line = next_old_match - 1,
              lines = deleted,
            })
          end
        else
          -- Modified line
          table.insert(changes, {
            type = "modify",
            start = i,
            end_line = i,
            old_lines = { old_lines[i] },
            new_lines = { new_lines[j] },
          })
          i = i + 1
          j = j + 1
        end
      end
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

  if current_tick == buffer.changedtick then
    return nil
  end

  local changes = detect_changes(buffer.last_sent, current_content)

  -- Update states
  buffer.content = current_content
  buffer.last_sent = current_content
  buffer.changedtick = current_tick

  return changes
end

return Watcher
