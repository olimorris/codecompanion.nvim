local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")

---@class CodeCompanion.Chat.UI.Formatters.Reasoning : CodeCompanion.Chat.UI.Formatters.Base
local Reasoning = BaseFormatter:new(chat)
Reasoning.__class = "Reasoning"

function Reasoning:can_handle(data, opts)
  return data.reasoning ~= nil
end

function Reasoning:get_tag()
  return self.chat.MESSAGE_TAGS.LLM_MESSAGE -- Reasoning is part of LLM response
end

function Reasoning:format(data, opts)
  local lines = {}

  -- Add reasoning header if this is the first reasoning in this cycle
  if not self.chat._has_reasoning_output then
    table.insert(lines, "### Reasoning")
    table.insert(lines, "")
  end
  self.chat._has_reasoning_output = true

  -- Add reasoning content
  for _, line in ipairs(vim.split(data.reasoning, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  return lines, nil
end

return Reasoning
