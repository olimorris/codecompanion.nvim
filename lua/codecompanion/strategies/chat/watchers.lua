--[[
Watchers track changes in Neovim buffers by comparing buffer content over time. It maintains
a state for each watched buffer, recording the current content and last sent content. When
checked, it compares states to detect line additions, deletions, and modifications.
]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format

---@class CodeCompanion.Watchers
local Watchers = {}

function Watchers.new()
  return setmetatable({
    buffers = {},
    augroup = api.nvim_create_augroup("codecompanion.watchers", { clear = true }),
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

---Get any changes in a watched buffer
---@param bufnr number
---@return boolean, table|nil
function Watchers:get_changes(bufnr)
  if not self.buffers[bufnr] then
    return false, nil
  end
  if not api.nvim_buf_is_valid(bufnr) then
    -- special case for unlisted buffers
    self:unwatch(bufnr)
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
  -- Use vim.diff to generate clean unified diff
  local diff_result = vim.diff(old_str, new_str, {
    result_type = "unified",
    ctxlen = 3, -- 3 lines of context
    algorithm = "myers",
  })
  if diff_result and diff_result ~= "" then
    return fmt("```diff\n%s```", diff_result)
  end

  return ""
end

---Check all watched buffers for changes
---@param chat CodeCompanion.Chat
function Watchers:check_for_changes(chat)
  for _, ref in ipairs(chat.refs) do
    if ref.bufnr and ref.opts and ref.opts.watched then
      local has_changed, old_content = self:get_changes(ref.bufnr)

      if has_changed and old_content then
        local filename = vim.fn.fnamemodify(api.nvim_buf_get_name(ref.bufnr), ":.")
        local current_content = api.nvim_buf_get_lines(ref.bufnr, 0, -1, false)
        local diff_content = format_changes_as_diff(old_content, current_content)

        if diff_content ~= "" then
          local delta = fmt("The file `%s`, has been modified. Here are the changes:\n%s", filename, diff_content)
          chat:add_message({
            role = config.constants.USER_ROLE,
            content = fmt([[<attachment filepath="%s" buffer_number="%s">%s</attachment>]], filename, ref.bufnr, delta),
          }, { visible = false })
        end
      elseif has_changed then
        -- buffer is now invalid
        chat:add_message({
          role = config.constants.USER_ROLE,
          content = fmt([[buffer %d has been removed.]], ref.bufnr),
        }, { visible = false })
      end
    end
  end
end

return Watchers
