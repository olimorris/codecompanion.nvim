local Reasoning = require("codecompanion.strategies.chat.ui.formatters.reasoning")
local Standard = require("codecompanion.strategies.chat.ui.formatters.standard")
local Tools = require("codecompanion.strategies.chat.ui.formatters.tools")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Chat.UI.Builder
---@field chat CodeCompanion.Chat
---@field current_tag? string
---@field data table
---@field fold_info? table
---@field is_new_response boolean
---@field lines table
---@field opts table
local Builder = {}

---@class CodeCompanion.Chat.UI.BuilderArgs
---@field chat CodeCompanion.Chat
---@field data table
---@field opts table
function Builder.new(args)
  return setmetatable({
    chat = args.chat,
    current_tag = nil,
    data = args.data or {},
    fold_info = nil,
    is_new_response = false,
    lines = {},
    opts = args.opts or {},
  }, { __index = Builder })
end

---Add header if needed based on role change
---@return CodeCompanion.Chat.UI.Builder
function Builder:add_header()
  local needs_header = (self.data.role and self.data.role ~= self.chat._last_role)
    or (self.opts and self.opts.force_role)

  if needs_header then
    self.is_new_response = true

    -- Add appropriate spacing based on last tag
    if self.chat._last_tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT then
      table.insert(self.lines, "")
    else
      table.insert(self.lines, "")
      table.insert(self.lines, "")
    end

    -- Update the chat's last role
    self.chat._last_role = self.data.role

    -- Set the header
    self.chat.ui:set_header(self.lines, config.strategies.chat.roles[self.data.role])
  end

  return self
end

---Format content using appropriate formatter
---@return CodeCompanion.Chat.UI.Builder
function Builder:format_content()
  if not (self.data.content or self.data.reasoning) then
    return self
  end

  local formatter = self:_get_formatter()
  local content_lines, fold_info = formatter:safe_format(self.data, self.opts, self.chat)

  vim.list_extend(self.lines, content_lines)
  if fold_info then
    self.fold_info = fold_info
  end

  self.current_tag = formatter:get_tag()

  return self
end

---Write the built content to buffer
---@return CodeCompanion.Chat.UI.Builder
function Builder:write_to_buffer()
  if vim.tbl_isempty(self.lines) then
    return self
  end

  self.chat.ui:unlock_buf()
  local last_line, last_column, line_count = self.chat.ui:last()

  if self.opts and self.opts.insert_at then
    last_line = self.opts.insert_at
    last_column = 0
  end

  local cursor_moved = vim.api.nvim_win_get_cursor(0)[1] == line_count
  vim.api.nvim_buf_set_text(self.chat.bufnr, last_line, last_column, last_line, last_column, self.lines)

  -- Handle folding for tool output
  if self.fold_info and self.opts and self.opts.tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT and #self.lines > 1 then
    local fold_start = last_line + self.fold_info.start_offset
    local fold_end = last_line + self.fold_info.end_offset
    self.chat.ui.tools:create_fold(fold_start, fold_end, self.fold_info.first_line)
  end

  -- Render headers if this is a new response
  if self.is_new_response then
    self.chat.ui:render_headers()
  end

  -- Lock buffer if not user role
  if self.chat._last_role ~= config.constants.USER_ROLE then
    self.chat.ui:lock_buf()
  end

  self.chat.ui:move_cursor(cursor_moved)

  return self
end

---Update the chat's tag state
---@return CodeCompanion.Chat.UI.Builder
function Builder:update_tag()
  if self.current_tag and self.data.content ~= "" then
    log:trace("[TAG CHANGE] %s -> %s (from %s formatter)", self.chat._last_tag, self.current_tag, self.current_tag)
    self.chat._last_tag = self.current_tag
  end

  return self
end

---Get the appropriate formatter for the data/opts
---@return CodeCompanion.Chat.UI.Formatters.Base
function Builder:_get_formatter()
  local formatters = {
    Tools:new(self.chat),
    Reasoning:new(self.chat),
    Standard:new(self.chat), -- Always last (fallback)
  }

  for _, formatter in ipairs(formatters) do
    if formatter:can_handle(self.data, self.opts) then
      return formatter
    end
  end

  return Standard:new(self.chat)
end

return Builder
