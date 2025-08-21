local config = require("codecompanion.config")

local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")
local Spacing = require("codecompanion.strategies.chat.ui.spacing")

---@class CodeCompanion.Chat.UI.Formatters.Tools : CodeCompanion.Chat.UI.Formatters.Base
local Tools = setmetatable({}, { __index = BaseFormatter })
Tools.__class = "Tools"

function Tools:can_handle(message, opts, tags)
  return opts and opts.type == tags.TOOL_MESSAGE
end

function Tools:get_type()
  return self.chat.MESSAGE_TYPES.TOOL_MESSAGE
end

function Tools:format(message, opts, state)
  local lines = {}

  -- Build spacing context for consistent spacing management
  local spacing_context = {
    is_new_role = false, -- Tools are always under LLM role
    is_new_section = state.is_new_section,
    previous_type = state.last_type,
    current_type = self:get_type(),
    has_reasoning_transition = state.has_reasoning_output,
    is_reasoning_start = false,
  }

  -- Handle reasoning to response transition
  if state.has_reasoning_output then
    state:mark_reasoning_complete()
    local transition_spacing = Spacing.get_pre_content_spacing(spacing_context, self.chat.MESSAGE_TYPES)
    vim.list_extend(lines, transition_spacing)
    table.insert(lines, "### Response")
  end

  -- Get pre-content spacing (but not for reasoning transitions as they're handled above)
  if not state.has_reasoning_output then
    local pre_spacing = Spacing.get_pre_content_spacing(spacing_context, self.chat.MESSAGE_TYPES)
    vim.list_extend(lines, pre_spacing)
  end

  local content_start = #lines + 1
  local content = message.content or ""
  for _, line in ipairs(vim.split(content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  -- Get post-content spacing
  local post_spacing = Spacing.get_post_content_spacing(spacing_context, self.chat.MESSAGE_TYPES)
  vim.list_extend(lines, post_spacing)

  if not config.strategies.chat.tools.opts.folds.enabled then
    return lines, nil
  end

  -- Folds can only work up to the penultimate line in the buffer, so we need
  -- to account for the trailing spacing in fold calculations
  local content_lines = vim.split(content, "\n", { plain = true, trimempty = false })
  local content_end = content_start + #content_lines - 1

  local fold_info = nil
  if content_end >= content_start and #content_lines > 1 then
    fold_info = {
      start_offset = content_start - 1, -- 0-based index
      end_offset = content_end - 1, -- 0-based index
      first_line = lines[content_start] or "",
    }
  end

  return lines, fold_info
end

return Tools
end

return Tools
