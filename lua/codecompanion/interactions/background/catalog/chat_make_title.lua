local log = require("codecompanion.utils.log")

local fmt = string.format

local M = {}

---Format the messages from a chat buffer
---@param messages CodeCompanion.Chat.Messages
function M.format_messages(messages)
  local chat_messages = {}
  for _, message in ipairs(messages or {}) do
    table.insert(chat_messages, fmt("## %s\n%s", message.role, message.content))
  end
  return table.concat(chat_messages, "\n")
end

---Handle the result from the title generation request
---@param result table
---@return string|nil
function M.on_done(result)
  if not result or (result.status and result.status == "error") then
    return
  end

  local title = result and result.output and result.output.content
  if title then
    title = title:match("^%s*[\"']?(.-)[\"']?%s*$")
    return title and title ~= "" and title or nil
  end
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
      content = [[You are a title generator. Review the conversation and generate a concise title.

Constraints:
- Max 50 characters.
- The conversation may be about coding, writing, analysis, or general questions.
- Focus on the user's core intent.
- Output ONLY the raw text of the title.
- Do NOT use quotation marks, markdown, or prefixes like "Title:".]],
    },
    {
      role = "user",
      content = fmt([[<conversation>%s</conversation]], M.format_messages(chat.messages)),
    },
  }, {
    method = "async",
    silent = true,
    on_done = function(result)
      local title = M.on_done(result)
      if title then
        chat:set_title(title)
        -- TODO: Remove the callback from the chat buffer
        log:debug("[Background] Chat title generated: %s", title)
      end
    end,
    on_error = function(err)
      log:debug("[Background] Chat title generation failed: %s", err)
    end,
  })
end

return M
