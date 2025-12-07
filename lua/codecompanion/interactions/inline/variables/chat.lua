local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

local llm_role = config.constants.LLM_ROLE

---@class CodeCompanion.Inline.Variables.Chat: CodeCompanion.Inline.Variables
local Chat = {}

---@param args CodeCompanion.Inline.VariablesArgs
function Chat.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = Chat })
end

---Get the last chat message
---@return string|nil
function Chat:output()
  local chat = codecompanion.last_chat()
  if not chat then
    return
  end

  local messages = ""
  vim
    .iter(chat.messages)
    :filter(function(v)
      return v.role == llm_role
    end)
    :map(function(v)
      messages = messages .. "\n\n## You\n\n" .. v.content
    end)

  return string.format(
    [[Below are some messages that you sent to me earlier which may be relevant to my user prompt:

---
%s]],
    messages
  )
end

return Chat
