local log = require("codecompanion.utils.log")

local fmt = string.format

local M = {}

---Format the messages from a chat buffer
---@param messages CodeCompanion.Chat.Messages
local function format_messages(messages)
  local chat_messages = {}
  for _, message in ipairs(messages or {}) do
    table.insert(chat_messages, fmt("## %s\n%s", message.role, message.content))
  end
  return table.concat(chat_messages, "\n")
end

---Make the request to generate a title for the chat
---@param background CodeCompanion.Background
---@param chat CodeCompanion.Chat
function M.request(background, chat)
  if chat.title and chat.title ~= "" then
    return
  end

  background:ask({
    {
      role = "system",
      content = [[You are an expert at summarising conversations. Your task is to generate a concise and relevant title for the conversation provided in the user's message.

Constraints:
- The title must be brief, ideally under 5 words.
- It must accurately reflect the main topic of the conversation.
- You must only output the title, with no additional text, quotation marks, or formatting.]],
    },
    {
      role = "user",
      content = fmt([[<conversation>%s</conversation]], format_messages(chat.messages)),
    },
  }, {
    method = "async",
    silent = true,
    on_done = function(result)
      if not result or (result.status and result.status == "error") then
        return
      end

      local title = result and result.output and result.output.content
      if title then
        title = title:gsub("^[\"']", ""):gsub("[\"']$", ""):gsub("^%s*", ""):gsub("%s*$", "")
        chat:set_title(title)

        -- Remove the callback from the chat buffer
      end
    end,
    on_error = function(err)
      log:debug("[Background] Chat title generation failed: %s", err)
    end,
  })
end

return M
