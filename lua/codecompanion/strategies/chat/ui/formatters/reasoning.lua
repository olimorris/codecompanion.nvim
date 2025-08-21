local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")
local Spacing = require("codecompanion.strategies.chat.ui.spacing")

---@class CodeCompanion.Chat.UI.Formatters.Reasoning : CodeCompanion.Chat.UI.Formatters.Base
local Reasoning = setmetatable({}, { __index = BaseFormatter })
Reasoning.__class = "Reasoning"

function Reasoning:can_handle(message, opts, tags)
  return opts and opts.type == tags.REASONING_MESSAGE
end

function Reasoning:get_type()
  return self.chat.MESSAGE_TYPES.REASONING_MESSAGE
end

function Reasoning:format(message, opts, state)
  local lines = {}

  -- Build spacing context
  local spacing_context = {
    is_new_role = false, -- Reasoning is always under LLM role
    is_new_section = state.is_new_section,
    previous_type = state.last_type,
    current_type = self:get_type(),
    has_reasoning_transition = false, -- We're starting reasoning, not transitioning from it
    is_reasoning_start = not state.has_reasoning_output,
  }

  -- Add reasoning header if this is the start of reasoning output
  if not state.has_reasoning_output then
    table.insert(lines, "### Reasoning")
    table.insert(lines, "")
    state:mark_reasoning_started()
  end

  -- Add reasoning content directly (no additional spacing needed)
  for _, line in ipairs(vim.split(message.content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  return lines, nil
end

return Reasoning
end

return Reasoning
