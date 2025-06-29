local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")

---@class CodeCompanion.Chat.UI.Formatters.Standard : CodeCompanion.Chat.UI.Formatters.Base
local Standard = BaseFormatter:new(chat)
Standard.__class = "Standard"

function Standard:can_handle(data, opts)
  return data.content ~= nil -- Has content to display
end

function Standard:get_tag(opts)
  -- Default to LLM message, but could be overridden by opts
  return (opts and opts.tag) or self.chat.MESSAGE_TAGS.LLM_MESSAGE
end

function Standard:format(data, opts)
  local lines = {}

  -- Handle transition from reasoning to response
  if self.chat._has_reasoning_output then
    self.chat._has_reasoning_output = false
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, "### Response")
    table.insert(lines, "")
  elseif self.chat._last_tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT then
    table.insert(lines, "")
  end

  -- Add content
  for _, line in ipairs(vim.split(data.content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  return lines, nil
end

return Standard
