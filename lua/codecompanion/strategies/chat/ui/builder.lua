--[[
===============================================================================
    File:       codecompanion/strategies/chat/ui/builder.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module builds out and formats the chat buffer's messages.

      It uses the notion of "sections" which defines content under a H2 header
      and "blocks" which are groups of messages of the same type, which sit
      under a section. There are three types of message:
        - LLM_MESSAGE: standard LLM output
        - REASONING_MESSAGE: internal reasoning steps
        - TOOL_MESSAGE: output from a tool call
===============================================================================
--]]
local config = require("codecompanion.config")

local Reasoning = require("codecompanion.strategies.chat.ui.formatters.reasoning")
local Standard = require("codecompanion.strategies.chat.ui.formatters.standard")
local Tools = require("codecompanion.strategies.chat.ui.formatters.tools")

local api = vim.api

local EPHEMERAL_STATE = {
  __index = {
    update_role = function(self, role)
      self.last_role = role
      self.is_new_response = true
    end,
    mark_reasoning_complete = function(self)
      self.has_reasoning_output = false
    end,
    mark_reasoning_started = function(self)
      self.has_reasoning_output = true
    end,
    update_type = function(self, type)
      self.last_type = type
    end,
    start_new_block = function(self)
      self.is_new_block = true
    end,
  },
}

---@class CodeCompanion.Chat.UI.Builder
---@field chat CodeCompanion.Chat
---@field state CodeCompanion.Chat.UI.BuilderState
---@field _formatters CodeCompanion.Chat.UI.Formatters.Base[]
---@field _fmt_state table
local Builder = {}

-- Type additions (place near the other annotations in builder.lua)
---@class CodeCompanion.Chat.UI.BuilderState
---@field last_role? string
---@field last_type? string
---@field has_reasoning_output boolean
---@field last_block_type? string
---@field current_block_type? string
---@field chunks_in_block number
---@field total_chunks number
---@field section_index number
---@field block_index number
---@field last_write_start number -- 0-based
---@field last_write_end number -- 0-based
---@field current_section_start? number -- 0-based
---@field last_section_start? number -- 0-based

---@class CodeCompanion.Chat.UI.BuilderArgs
---@field chat CodeCompanion.Chat
---@field state table
function Builder.new(args)
  return setmetatable({
    chat = args.chat,
    state = {
      last_role = args.chat._last_role,
      last_type = nil,
      has_reasoning_output = false,

      -- Block tracking
      last_block_type = nil,
      current_block_type = nil,
      chunks_in_block = 0,
      total_chunks = 0,

      -- Section tracking
      section_index = 0,
      block_index = 0,

      -- Write bounds
      last_write_start = 0,
      last_write_end = 0,
      current_section_start = nil,
      last_section_start = nil,
    },

    -- Cache the formatter instances
    _formatters = {
      Tools:new(args.chat),
      Reasoning:new(args.chat),
      Standard:new(args.chat),
    },
    _fmt_state = setmetatable({}, EPHEMERAL_STATE),
  }, { __index = Builder })
end

---Create a rich formatting state object for this cycle in the chat buffer
---@param out table The reusable ephemeral state table
---@param base_state table The persistent state from builder
---@return table Rich formatting state with methods
local function create_state(out, base_state)
  local state = out

  state.last_role = base_state.last_role
  state.last_type = base_state.last_type
  state.has_reasoning_output = base_state.has_reasoning_output

  -- Block tracking
  state.last_block_type = base_state.last_block_type
  state.current_block_type = base_state.current_block_type
  state.chunks_in_block = base_state.chunks_in_block or 0
  state.total_chunks = base_state.total_chunks or 0

  -- Section tracking
  state.section_index = base_state.section_index or 0
  state.block_index = base_state.block_index or 0

  -- Block-local flags
  state.last_block = nil
  state.current_block = nil
  state.is_new_response = false
  state.is_new_block = false

  return state
end

---Add message using centralized state
---@param data table
---@param opts table
---@return nil
function Builder:add_message(data, opts)
  opts = opts or {}
  local lines, fold_info, current_type, formatter = {}, nil, nil, nil

  local state = create_state(self._fmt_state, self.state)

  local needs_header = self:_should_add_header(data, opts, state)
  local needs_block = self:_should_start_new_block(opts, state)

  if needs_header then
    state:update_role(data.role)
    self:_add_header_spacing(lines, state)
    self.chat.ui:set_header(lines, config.strategies.chat.roles[data.role])

    -- Section started: reset block trackers
    self.state.section_index = (self.state.section_index or 0) + 1
    self.state.block_index = 0
    self.state.current_block_type = nil
    self.state.chunks_in_block = 0

    -- Mirror resets into ephemeral state so formatters see correct indices
    state.section_index = self.state.section_index
    state.block_index = 0
    state.current_block_type = nil
    state.chunks_in_block = 0

    -- We intentionally do NOT set is_new_block in the same message as a role header
  elseif needs_block then
    state:start_new_block()
  end

  local has_content = data.content or (data.reasoning and data.reasoning.content)

  --log:info("[Builder] state %s", state)

  if has_content then
    formatter = self:_get_formatter(data, opts)
    local content_lines, content_fold_info = formatter:format(data, opts, state)

    vim.list_extend(lines, content_lines)
    if content_fold_info then
      fold_info = content_fold_info
    end

    -- This role check is more of a testing fix than a real logic check
    if data.content ~= "" and data.role ~= config.constants.USER_ROLE then
      current_type = formatter:get_type(opts)
    end
  end

  if not vim.tbl_isempty(lines) then
    self:_write_to_buffer(lines, opts, fold_info, state)
  end

  if current_type then
    -- Update type for next decision
    state:update_type(current_type)

    -- Block tracking: treat role changes and type changes as new blocks
    self.state.total_chunks = (self.state.total_chunks or 0) + 1
    local is_new_block = state.is_new_response or (self.state.current_block_type ~= current_type)

    if is_new_block then
      self.state.last_block_type = self.state.current_block_type
      self.state.current_block_type = current_type
      self.state.chunks_in_block = 1
      self.state.block_index = (self.state.block_index or 0) + 1
    else
      self.state.chunks_in_block = (self.state.chunks_in_block or 0) + 1
    end
  end

  self:_sync_state_from_formatting_state(state)
  self:_sync_state_to_chat()
end

---Determine if we should start a new block under the header
---@param opts table
---@param state table
---@return boolean
function Builder:_should_start_new_block(opts, state)
  return opts.type ~= nil and opts.type ~= state.last_type
end

---Check if we need to add a header to the chat buffer
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
  table.insert(lines, "")
  table.insert(lines, "")
end

---Get the appropriate formatter
---@param data table
---@param opts table
---@return CodeCompanion.Chat.UI.Formatters.Base
function Builder:_get_formatter(data, opts)
  for _, formatter in ipairs(self._formatters) do
    if formatter:can_handle(data, opts, self.chat.MESSAGE_TYPES) then
      return formatter
    end
  end
  return self._formatters[#self._formatters]
end

---Write lines to buffer with all the buffer management
---@param lines table
---@param opts table
---@param fold_info table|nil
---@param state table
function Builder:_write_to_buffer(lines, opts, fold_info, state)
  self.chat.ui:unlock_buf()
  local last_line, last_column, line_count = self.chat.ui:last()

  local insert_line = last_line
  if opts.insert_at then
    insert_line = opts.insert_at
    last_column = 0
  end

  local cursor_moved = api.nvim_win_get_cursor(0)[1] == line_count

  if opts._icon_info and opts._icon_info.has_icon then
    vim.schedule(function()
      local Icons = require("codecompanion.strategies.chat.ui.icons")
      local target_line = last_line + (opts._icon_info.line_offset or 0)
      Icons.apply_tool_icon(self.chat.bufnr, target_line, opts._icon_info.status)
    end)
  end

  api.nvim_buf_set_text(self.chat.bufnr, insert_line, last_column, insert_line, last_column, lines)

  -- Record write bounds
  local end_line_written = insert_line + (#lines > 0 and (#lines - 1) or 0)
  self.state.last_write_start = insert_line
  self.state.last_write_end = end_line_written

  -- If a new role header was rendered, update section anchors and headers
  if state.is_new_response then
    self.state.last_section_start = self.state.current_section_start
    self.state.current_section_start = insert_line
    self.chat.ui:render_headers()
  end

  -- Tool folds
  if fold_info then
    local fold_start = insert_line + fold_info.start_offset
    local fold_end = insert_line + fold_info.end_offset
    vim.schedule(function()
      self.chat.ui.folds:create_tool_fold(self.chat.bufnr, fold_start, fold_end, fold_info.first_line)
    end)
  end

  -- Reasoning folds
  if self.state.has_reasoning_output and not state.has_reasoning_output and config.display.chat.fold_reasoning then
    local range_start = self.state.current_section_start or 0
    local range_end = insert_line
    vim.schedule(function()
      self.chat.ui.folds:create_reasoning_fold(self.chat, range_start, range_end)
    end)
  end

  if state.last_role ~= config.constants.USER_ROLE then
    self.chat.ui:lock_buf()
  end

  self.chat.ui:move_cursor(cursor_moved)
end

---Sync formatting state back to builder's persistent state
---@param state table
function Builder:_sync_state_from_formatting_state(state)
  self.state.has_reasoning_output = state.has_reasoning_output
  self.state.last_role = state.last_role
  self.state.last_type = state.last_type
end

---Sync builder state back to chat object for persistence
function Builder:_sync_state_to_chat()
  self.chat._last_role = self.state.last_role
end

return Builder
