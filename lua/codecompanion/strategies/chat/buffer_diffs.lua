--[[
  Syncs buffer changes by tracking diffs between buffer states.
  Detects line additions, deletions, and modifications.
]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format
local diff = vim.text.diff or vim.diff

---@class CodeCompanion.BufferDiffs
---@field buffers table<number, CodeCompanion.BufferDiffs.State> Map of buffer numbers to their states
---@field augroup integer The autocmd group ID
---@field sync fun(self: CodeCompanion.BufferDiffs, bufnr: number): nil Start syncing a buffer
---@field unsync fun(self: CodeCompanion.BufferDiffs, bufnr: number): nil Stop syncing a buffer
---@field get_changes fun(self: CodeCompanion.BufferDiffs, bufnr: number): boolean, table

---@class CodeCompanion.BufferDiffs.State
---@field content string[] Complete buffer content
---@field changedtick number Last known changedtick
---@field last_sent string[] Last content sent to LLM

---@class CodeCompanion.BufferDiffs
local BufferDiffs = {}

function BufferDiffs.new()
  return setmetatable({
    buffers = {},
    augroup = api.nvim_create_augroup("codecompanion.buffer_diffs", { clear = true }),
  }, { __index = BufferDiffs })
end

---Sync with a buffer to watch for changes
---@param bufnr number
---@return nil
function BufferDiffs:sync(bufnr)
  if self.buffers[bufnr] then
    return
  end

  if not api.nvim_buf_is_valid(bufnr) then
    return log:debug("Cannot sync invalid buffer: %d", bufnr)
  end

  log:debug("Starting to sync buffer: %d", bufnr)
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
      self:unsync(bufnr)
    end,
  })
end

---Stop syncing a buffer
---@param bufnr number
---@return nil
function BufferDiffs:unsync(bufnr)
  if self.buffers[bufnr] then
    log:debug("Unsyncing buffer %d", bufnr)
    self.buffers[bufnr] = nil
  end
end

---Check if buffer content has changed
---@param old_content table
---@param new_content table
---@return boolean
local function has_changes(old_content, new_content)
  if #old_content ~= #new_content then
    return true
  end
  for i = 1, #old_content do
    if old_content[i] ~= new_content[i] then
      return true
    end
  end
  return false
end

---Get any changes in a synced buffer
---@param bufnr number
---@return boolean, table|nil
function BufferDiffs:get_changes(bufnr)
  if not self.buffers[bufnr] then
    return false, nil
  end
  if not api.nvim_buf_is_valid(bufnr) then
    -- special case for unlisted buffers
    self:unsync(bufnr)
    return true, nil
  end

  local buffer = self.buffers[bufnr]

  local current_content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_tick = api.nvim_buf_get_changedtick(bufnr)
  if current_tick == buffer.changedtick then
    return false, nil
  end

  local old_content = buffer.last_sent -- Store before updating

  local changed = has_changes(old_content, current_content)
  if changed then
    buffer.content = current_content
    buffer.last_sent = current_content
    buffer.changedtick = current_tick
    return true, old_content
  end

  return false, nil
end

---Generate unified diff using vim.diff
---@param old_content table
---@param new_content table
---@return string
local function format_changes_as_diff(old_content, new_content)
  -- Convert line arrays to strings for vim.diff
  local old_str = table.concat(old_content, "\n") .. "\n"
  local new_str = table.concat(new_content, "\n") .. "\n"

  local diff_result = diff(old_str, new_str, {
    result_type = "unified",
    ctxlen = 3,
    algorithm = "myers",
  })

  if diff_result and diff_result ~= "" then
    return fmt("````diff\n%s````", diff_result)
  end

  return ""
end

---Check all synced buffers for changes
---@param chat CodeCompanion.Chat
function BufferDiffs:check_for_changes(chat)
  for _, item in ipairs(chat.context_items) do
    if item.bufnr and item.opts and item.opts.sync_diff then
      local has_changed, old_content = self:get_changes(item.bufnr)

      if has_changed and old_content then
        local filename = vim.fn.fnamemodify(api.nvim_buf_get_name(item.bufnr), ":.")
        local current_content = api.nvim_buf_get_lines(item.bufnr, 0, -1, false)
        local diff_content = format_changes_as_diff(old_content, current_content)

        if diff_content ~= "" then
          local delta = fmt("The file `%s`, has been modified. Here are the changes:\n%s", filename, diff_content)
          chat:add_message({
            role = config.constants.USER_ROLE,
            content = fmt(
              [[<attachment filepath="%s" buffer_number="%s">%s</attachment>]],
              filename,
              item.bufnr,
              delta
            ),
          }, { context = { id = item.id }, visible = false })
        end
      elseif has_changed then
        chat:add_message({
          role = config.constants.USER_ROLE,
          content = fmt([[Buffer %d has been removed.]], item.bufnr),
        }, { visible = false })
      end
    end
  end
end

return BufferDiffs
