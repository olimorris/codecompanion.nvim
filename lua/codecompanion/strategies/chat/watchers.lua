--[[
Watchers track changes in Neovim buffers by comparing buffer content over time. It maintains
a state for each watched buffer, recording the current content and last sent content. When
checked, it compares states to detect line additions, deletions, and modifications.
]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api

---Find the index of a line in a list of lines
---@param line string
---@param lines table
---@param start_idx number
---@return number|nil
local function find_line_match(line, lines, start_idx)
  for i = start_idx or 1, #lines do
    if lines[i] == line then
      return i
    end
  end
  return nil
end

---Detect changes between two sets of lines
---@param old_lines table
---@param new_lines table
---@return CodeCompanion.WatcherChange[]
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

---@class CodeCompanion.Watchers
local Watchers = {}

function Watchers.new()
  return setmetatable({
    buffers = {},
    augroup = api.nvim_create_augroup("CodeCompanionWatcher", { clear = true }),
  }, { __index = Watchers })
end

---Watch a buffer for changes
---@param bufnr number
---@return nil
function Watchers:watch(bufnr)
  if self.buffers[bufnr] then
    return
  end

  if not api.nvim_buf_is_valid(bufnr) then
    log:debug("Cannot watch invalid buffer: %d", bufnr)
    return
  end

  log:debug("Starting to watch buffer: %d", bufnr)
  local initial_content = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  self.buffers[bufnr] = {
    content = initial_content,
    last_sent = initial_content,
    changedtick = api.nvim_buf_get_changedtick(bufnr),
  }

  api.nvim_create_autocmd("BufDelete", {
    group = self.augroup,
    buffer = bufnr,
    callback = function()
      self:unwatch(bufnr)
    end,
  })
end

---Stop watching a buffer
---@param bufnr number
---@return nil
function Watchers:unwatch(bufnr)
  if self.buffers[bufnr] then
    log:debug("Unwatching buffer %d", bufnr)
    self.buffers[bufnr] = nil
  end
end

---Get any changes in a watched buffer
---@param bufnr number
---@return CodeCompanion.WatcherChange[]|nil
function Watchers:get_changes(bufnr)
  if not self.buffers[bufnr] then
    return nil
  end

  local buffer = self.buffers[bufnr]
  local current_content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_tick = api.nvim_buf_get_changedtick(bufnr)

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

---Check all watched buffers for changes
---@param chat CodeCompanion.Chat
function Watchers:check_for_changes(chat)
  for _, ref in ipairs(chat.refs) do
    if ref.bufnr and ref.opts and ref.opts.watched then
      local changes = self:get_changes(ref.bufnr)
      log:debug("Checking watched buffer %d, found %d changes", ref.bufnr, changes and #changes or 0)

      if changes and #changes > 0 then
        local changes_text = string.format(
          "Changes detected in `%s` (buffer %d):\n",
          vim.fn.fnamemodify(api.nvim_buf_get_name(ref.bufnr), ":t"),
          ref.bufnr
        )

        for _, change in ipairs(changes) do
          if change.type == "delete" then
            changes_text = changes_text
              .. string.format(
                "Lines %d-%d were deleted:\n```%s\n%s\n```\n",
                change.start,
                change.end_line,
                vim.bo[ref.bufnr].filetype,
                table.concat(change.lines, "\n")
              )
          elseif change.type == "modify" then
            changes_text = changes_text
              .. string.format(
                "Lines %d-%d were modified from:\n```%s\n%s\n```\nto:\n```%s\n%s\n```\n",
                change.start,
                change.end_line,
                vim.bo[ref.bufnr].filetype,
                table.concat(change.old_lines, "\n"),
                vim.bo[ref.bufnr].filetype,
                table.concat(change.new_lines, "\n")
              )
          else -- type == "add"
            changes_text = changes_text
              .. string.format(
                "Lines %d-%d were added:\n```%s\n%s\n```\n",
                change.start,
                change.end_line,
                vim.bo[ref.bufnr].filetype,
                table.concat(change.lines, "\n")
              )
          end
        end

        chat:add_message({
          role = config.constants.USER_ROLE,
          content = changes_text,
        }, { visible = false })
      end
    end
  end
end

return Watchers
