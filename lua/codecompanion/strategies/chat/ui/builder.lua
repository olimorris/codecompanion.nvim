local config = require("codecompanion.config")

local Reasoning = require("codecompanion.strategies.chat.ui.formatters.reasoning")
local Standard = require("codecompanion.strategies.chat.ui.formatters.standard")
local Tools = require("codecompanion.strategies.chat.ui.formatters.tools")

---@class CodeCompanion.Chat.UI.Builder
---@field chat CodeCompanion.Chat
---@field state table
local Builder = {}

---@class CodeCompanion.Chat.UI.BuilderArgs
---@field chat CodeCompanion.Chat
---@field state table
function Builder.new(args)
  return setmetatable({
    chat = args.chat,
    state = {
      last_role = args.chat._last_role,
    },
  }, { __index = Builder })
end

---Create a rich formatting state object for this message
---@param base_state table The persistent state from builder
---@return table Rich formatting state with methods
local function create_state(base_state)
  local state = {
    -- Persistent state (copied from builder)
    last_role = base_state.last_role,
    last_tag = base_state.last_tag,
    has_reasoning_output = base_state.has_reasoning_output,

    -- Current context (gets set during formatting)
    is_new_response = false,
    is_new_section = false,
  }

  -- Helper methods
  function state:set_new_response()
    self.is_new_response = true
  end

  function state:update_role(role)
    self.last_role = role
    self.is_new_response = true
  end

  function state:mark_reasoning_complete()
    self.has_reasoning_output = false
  end

  function state:mark_reasoning_started()
    self.has_reasoning_output = true
  end

  function state:update_tag(tag)
    self.last_tag = tag
  end

  function state:start_new_section()
    self.is_new_section = true
  end

  return state
end

---Add message using centralized state
---@param data table
---@param opts table
---@return nil
function Builder:add_message(data, opts)
  opts = opts or {}
  local lines = {}
  local fold_info = nil
  local current_tag = nil

  -- Create rich formatting state for this message
  local state = create_state(self.state)

  local needs_header = self:_should_add_header(data, opts, state)
  local needs_new_section = self:_should_start_new_section(data, opts, state)

  if needs_header then
    state:update_role(data.role)
    self:_add_header_spacing(lines, state)
    self.chat.ui:set_header(lines, config.strategies.chat.roles[data.role])
  elseif needs_new_section then
    state:start_new_section()
  end

  -- Format content - pass rich state to formatters
  if data.content or data.reasoning then
    local formatter = self:_get_formatter(data, opts)
    local content_lines, content_fold_info = formatter:format(data, opts, state)

    vim.list_extend(lines, content_lines)
    if content_fold_info then
      fold_info = content_fold_info
    end
    current_tag = formatter:get_tag()
  end

  -- Write to buffer
  if not vim.tbl_isempty(lines) then
    self:_write_to_buffer(lines, opts, fold_info, state)
  end

  -- Update persistent state from rich state
  if current_tag and (data.content ~= "" or data.reasoning) then
    state:update_tag(current_tag)
  end

  -- Sync state back to builder for persistence
  self:_sync_state_from_formatting_state(state)
  self:_sync_state_to_chat()
end

---Determine if we should start a new section under the header
---@param data table
---@param opts table
---@param state table
---@return boolean
function Builder:_should_start_new_section(data, opts, state)
  if not opts.tag then
    return false
  end

  return opts.tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT and state.last_tag == self.chat.MESSAGE_TAGS.LLM_MESSAGE
end

---Check if we need a header
---@param data table
---@param opts table
---@param state table
---@return boolean
function Builder:_should_add_header(data, opts, state)
  return (data.role and data.role ~= state.last_role) or (opts and opts.force_role)
end

---Add appropriate spacing before header
---@param lines table
---@param state table
---@return nil
function Builder:_add_header_spacing(lines, state)
  if state.last_tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT then
    table.insert(lines, "")
  else
    table.insert(lines, "")
    table.insert(lines, "")
  end
end

---Get the appropriate formatter
---@param data table
---@param opts table
---@return CodeCompanion.Chat.UI.Formatters.Base
function Builder:_get_formatter(data, opts)
  local formatters = {
    Tools:new(self.chat),
    Reasoning:new(self.chat),
    Standard:new(self.chat),
  }

  for _, formatter in ipairs(formatters) do
    if formatter:can_handle(data, opts, self.chat.MESSAGE_TAGS) then
      return formatter
    end
  end

  return Standard:new(self.chat)
end

---Write lines to buffer with all the buffer management
---@param lines table
---@param opts table
---@param fold_info table|nil
---@param state table
function Builder:_write_to_buffer(lines, opts, fold_info, state)
  self.chat.ui:unlock_buf()
  local last_line, last_column, line_count = self.chat.ui:last()

  if opts.insert_at then
    last_line = opts.insert_at
    last_column = 0
  end

  local cursor_moved = vim.api.nvim_win_get_cursor(0)[1] == line_count
  vim.api.nvim_buf_set_text(self.chat.bufnr, last_line, last_column, last_line, last_column, lines)

  -- Handle folding
  if fold_info and opts.tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT and #lines > 1 then
    local fold_start = last_line + fold_info.start_offset
    local fold_end = last_line + fold_info.end_offset
    self.chat.ui.tools:create_fold(fold_start, fold_end, fold_info.first_line)
  end

  -- Render headers if new response
  if state.is_new_response then
    self.chat.ui:render_headers()
  end

  -- Lock buffer if not user role
  if state.last_role ~= config.constants.USER_ROLE then
    self.chat.ui:lock_buf()
  end

  self.chat.ui:move_cursor(cursor_moved)
end

---Sync formatting state back to builder's persistent state
---@param state table
function Builder:_sync_state_from_formatting_state(state)
  self.state.last_role = state.last_role
  self.state.last_tag = state.last_tag
  self.state.has_reasoning_output = state.has_reasoning_output
end

---Sync builder state back to chat object for persistence
function Builder:_sync_state_to_chat()
  self.chat._last_role = self.state.last_role
end

return Builder
