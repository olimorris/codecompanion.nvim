--[[
===============================================================================
    File:       codecompanion.interactions/chat/ui/builder.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      Renders the chat buffer's streamed output.

      A "section" is the content under a role header. Within a section, a
      "block" is a contiguous run of one logical type:
        - reasoning : the model's internal reasoning
        - llm       : standard LLM output
        - tool      : output from a tool call
===============================================================================
--]]
local Icons = require("codecompanion.interactions.chat.ui.icons")
local config = require("codecompanion.config")

local api = vim.api

-- The different types of blocks that are rendered in the chat buffer
local BLOCK = { REASONING = "reasoning", LLM = "llm", TOOL = "tool" }

local SUBHEADER = { REASONING = "### Reasoning", RESPONSE = "### Response" }
local BLANK = ""

-- Every blank line and sub-header in the chat buffer is decided here with a
-- separator(prev, new) format. It returns the lines that go between one
-- block's last line and a next block's first line. Unless there's a new section to add...
local FIRST_BLOCK = {
  [BLOCK.REASONING] = { SUBHEADER.REASONING, BLANK },
  [BLOCK.LLM] = {},
  [BLOCK.TOOL] = {},
}
local SEPARATORS = {
  [BLOCK.REASONING] = {
    [BLOCK.LLM] = { BLANK, SUBHEADER.RESPONSE, BLANK },
    [BLOCK.TOOL] = { BLANK, SUBHEADER.RESPONSE, BLANK },
  },
  [BLOCK.LLM] = {
    [BLOCK.REASONING] = { BLANK, SUBHEADER.REASONING, BLANK },
    [BLOCK.TOOL] = { BLANK },
  },
  [BLOCK.TOOL] = {
    [BLOCK.REASONING] = { BLANK, SUBHEADER.REASONING, BLANK },
    [BLOCK.LLM] = { BLANK },
    [BLOCK.TOOL] = { BLANK },
  },
}

---@param prev? string A `BLOCK` value, or nil for the first block in a section
---@param new string A `BLOCK` value
---@return string[]
local function separator(prev, new)
  if prev == nil then
    return FIRST_BLOCK[new]
  end
  local row = SEPARATORS[prev]
  return (row and row[new]) or {}
end

---@class CodeCompanion.Chat.UI.BuilderState
---@field last_role? string The role of the section currently being rendered
---@field block_type? string The `BLOCK` type of the open block; nil after a header
---@field current_section_start? number 0-based line where the current section begins
---@field current_header_line? number 0-based line holding the current role header

---@class CodeCompanion.Chat.UI.Builder
---@field chat CodeCompanion.Chat
---@field state CodeCompanion.Chat.UI.BuilderState
---@field _block_by_type table<string, string> Maps `MESSAGE_TYPES` to `BLOCK` values
local Builder = {}

---@class CodeCompanion.Chat.UI.BuilderArgs
---@field chat CodeCompanion.Chat
function Builder.new(args)
  local types = args.chat.MESSAGE_TYPES
  return setmetatable({
    chat = args.chat,
    state = {
      last_role = args.chat._last_role,
      block_type = nil,
      current_section_start = nil,
      current_header_line = nil,
    },
    _block_by_type = {
      [types.REASONING_MESSAGE] = BLOCK.REASONING,
      [types.TOOL_MESSAGE] = BLOCK.TOOL,
      [types.LLM_MESSAGE] = BLOCK.LLM,
    },
  }, { __index = Builder })
end

---Do we need to render a role header before this message?
---@param data { role?: string }
---@param opts { force_role?: boolean }
---@return boolean
function Builder:_needs_header(data, opts)
  return data.role ~= nil and (data.role ~= self.state.last_role or opts.force_role == true)
end

---Map a message's wire type to its logical block type, defaulting to prose
---@param opts { type?: string }
---@return string A `BLOCK` value
function Builder:_block_type(opts)
  return self._block_by_type[opts.type] or BLOCK.LLM
end

---Tool output folds unless folds are disabled or the tool carries a status (ACP)
---@param opts { status?: string }
---@return boolean
function Builder:_tool_folds_enabled(opts)
  return config.interactions.chat.tools.opts.folds.enabled and not opts.status
end

---Add a streamed message to the chat buffer
---@param data { content?: string, role?: string }
---@param opts? { type?: string, force_role?: boolean, insert_at?: number, status?: string, _icon_info?: table, virt_text_pos?: string }
---@return number|nil insert_line The line after the write (1-based), or nil if nothing was written
---@return number|nil icon_id
function Builder:add_message(data, opts)
  opts = opts or {}

  local role_changed = self:_needs_header(data, opts)

  local content = data.content
  -- If the role has changed (user <-> LLM) then start a new line
  local has_content = content ~= nil and (content ~= "" or role_changed)

  local block = has_content and self:_block_type(opts) or nil
  -- Each tool call is its own block even though the type repeats
  local new_block = has_content and (role_changed or block ~= self.state.block_type or block == BLOCK.TOOL)

  local write = {
    role_changed = role_changed,
    leaving_reasoning = block ~= nil and self.state.block_type == BLOCK.REASONING and block ~= BLOCK.REASONING,
  }

  local starts_new_line = role_changed or new_block
  local lines = {}
  if starts_new_line then
    table.insert(lines, BLANK)
  end

  local prev_block = self.state.block_type
  if role_changed then
    table.insert(lines, BLANK)
    self.chat.ui:set_header(lines, config.interactions.chat.roles[data.role])
    self.state.last_role = data.role
    self.state.block_type = nil
    prev_block = nil
  end

  if has_content then
    ---@cast block string
    local content_lines = vim.split(content, "\n", { plain = true, trimempty = false })
    if new_block then
      vim.list_extend(lines, separator(prev_block, block))
      -- NOTE: Some LLMs open a block with blank lines, sometimes split across chunks
      if content ~= BLANK then
        while content_lines[1] == BLANK do
          table.remove(content_lines, 1)
        end
      end
    end

    write.content_start = #lines
    vim.list_extend(lines, content_lines)

    if block == BLOCK.TOOL and #content_lines > 0 and self:_tool_folds_enabled(opts) then
      write.fold_info = {
        start_offset = write.content_start,
        end_offset = write.content_start + #content_lines - 1,
        first_line = content_lines[1] or "",
      }
    end

    self.state.block_type = block
  end

  if vim.tbl_isempty(lines) then
    return nil
  end

  -- If the line has a blank line at the end, don't add an additional one
  if starts_new_line then
    write.trailing_blanks = lines[2] == BLANK and 0 or 1
  end

  return self:_write(lines, opts, write)
end

---Trim or pad the buffer's trailing blank lines
---@param n number
function Builder:_set_trailing_blanks(n)
  local bufnr = self.chat.bufnr
  local count = api.nvim_buf_line_count(bufnr)

  local blanks = 0
  for i = count, 1, -1 do
    if api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] ~= "" then
      break
    end
    blanks = blanks + 1
  end

  -- Determine if there are any excess blank lines. If there are, remove them from the top
  -- Removing from the bottom clears extmarks that might be anchored
  if blanks > n then
    local first_blank = count - blanks
    api.nvim_buf_set_lines(bufnr, first_blank, first_blank + (blanks - n), false, {})
  elseif blanks < n then
    local pad = {}
    for _ = 1, n - blanks do
      pad[#pad + 1] = ""
    end
    api.nvim_buf_set_lines(bufnr, count, count, false, pad)
  end
end

---Write the assembled lines to the buffer and finalise icons, folds and headers
---@param lines string[]
---@param opts table The original message opts
---@param write { role_changed: boolean, content_start?: number, fold_info?: table, leaving_reasoning?: boolean, trailing_blanks?: number }
---@return number insert_line 1-based line after the write
---@return number|nil icon_id
function Builder:_write(lines, opts, write)
  self.chat.ui:unlock_buf()
  if write.trailing_blanks and not opts.insert_at then
    self:_set_trailing_blanks(write.trailing_blanks)
  end
  local last_line, last_column = self.chat.ui:last()

  local insert_line = opts.insert_at or last_line
  local column = opts.insert_at and 0 or last_column
  local was_following = self.chat.ui:is_following()

  api.nvim_buf_set_text(self.chat.bufnr, insert_line, column, insert_line, column, lines)

  local icon_id = self:_apply_icon(insert_line, opts, write.content_start)

  if write.role_changed then
    self.state.current_section_start = insert_line
    -- The write's first blank merges into the existing last line, so only the
    -- second blank costs a row before the header
    self.state.current_header_line = insert_line + 2
    self.chat.ui:render_headers()
  end

  if write.fold_info then
    local fold_start = insert_line + write.fold_info.start_offset
    local fold_end = insert_line + write.fold_info.end_offset
    vim.schedule(function()
      self.chat.ui.folds:create_tool_fold(self.chat.bufnr, fold_start, fold_end, write.fold_info.first_line)
    end)
  end

  if write.leaving_reasoning and config.display.chat.fold_reasoning then
    local range_start = self.state.current_section_start or 0
    vim.schedule(function()
      self.chat.ui.folds:create_reasoning_fold(self.chat, range_start, insert_line)
    end)
  end

  if self.state.last_role ~= config.constants.USER_ROLE then
    self.chat.ui:lock_buf()
  end
  self.chat.ui:move_cursor(was_following)
  self.chat._last_role = self.state.last_role

  return insert_line + #lines, icon_id
end

---Place a tool status icon on the block's first content line, if one is requested
---@param insert_line number 0-based line where the write began
---@param opts { status?: string, _icon_info?: table, virt_text_pos?: string }
---@param content_start? number Lines preceding the content within this write
---@return number|nil icon_id
function Builder:_apply_icon(insert_line, opts, content_start)
  local info = opts._icon_info
  local status = (info and info.has_icon and info.status) or opts.status
  if not status then
    return nil
  end

  local offset = (content_start or 0) + ((info and info.line_offset) or 0)
  return Icons.apply(self.chat.bufnr, insert_line + offset, status, { virt_text_pos = opts.virt_text_pos })
end

---Update a specific line in the chat buffer
---@param line_number number The line number to update (1-based)
---@param content string The new content for the line
---@param opts? { status?: string, icon_id?: number, priority?: number, virt_text_pos?: string }
---@return boolean success Whether the update was successful
---@return number|nil icon_id The new icon extmark ID, if an icon was placed
function Builder:update_line(line_number, content, opts)
  opts = opts or {}

  if line_number < 1 then
    return false
  end

  local zero_based_line = line_number - 1
  local line_count = api.nvim_buf_line_count(self.chat.bufnr)
  if zero_based_line >= line_count then
    return false
  end

  self.chat.ui:unlock_buf()

  local new_icon_id
  local ok, _ = pcall(api.nvim_buf_set_lines, self.chat.bufnr, zero_based_line, zero_based_line + 1, false, { content })
  if ok and opts.status then
    if opts.icon_id then
      pcall(api.nvim_buf_del_extmark, self.chat.bufnr, Icons.ns(), opts.icon_id)
    end
    Icons.clear_line(self.chat.bufnr, zero_based_line)
    new_icon_id = Icons.apply(self.chat.bufnr, zero_based_line, opts.status, opts)
  end

  if self.state.last_role ~= config.constants.USER_ROLE then
    self.chat.ui:lock_buf()
  end

  return true, new_icon_id
end

return Builder
