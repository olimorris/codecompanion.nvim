local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")
local Spacing = require("codecompanion.strategies.chat.ui.spacing")

---@class CodeCompanion.Chat.UI.Formatters.Standard : CodeCompanion.Chat.UI.Formatters.Base
local Standard = setmetatable({}, { __index = BaseFormatter })
Standard.__class = "Standard"

function Standard:can_handle(message, opts, tags)
  return message.content ~= nil -- Has content to display
end

function Standard:get_type(opts)
  -- Default to LLM message, but could be overridden by opts
  return (opts and opts.type) or self.chat.MESSAGE_TYPES.LLM_MESSAGE
end

function Standard:format(message, opts, state)
  local lines = {}

  -- Build spacing context
  local spacing_context = {
    is_new_role = false, -- Standard messages are typically under LLM role
    is_new_section = state.is_new_section,
    previous_type = state.last_type,
    current_type = self:get_type(opts),
    has_reasoning_transition = state.has_reasoning_output,
    is_reasoning_start = false,
  }

  -- Handle transition from reasoning to response
  if state.has_reasoning_output then
    state:mark_reasoning_complete()
    local transition_spacing = Spacing.get_pre_content_spacing(spacing_context, self.chat.MESSAGE_TYPES)
    vim.list_extend(lines, transition_spacing)
    table.insert(lines, "### Response")
    table.insert(lines, "")
  end

  -- Add content directly (spacing is handled at message boundary level)
  for _, line in ipairs(vim.split(message.content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  return lines, nil
end

return Standard
end

return Standard
