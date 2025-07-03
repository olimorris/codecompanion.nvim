local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")

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

  -- Handle transition from reasoning to response using rich state
  if state.has_reasoning_output then
    state:mark_reasoning_complete()
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, "### Response")
    table.insert(lines, "")
  end

  -- Add content
  for _, line in ipairs(vim.split(message.content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  return lines, nil
end

return Standard
