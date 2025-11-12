local fmt = string.format

local M = {}

---@param messages CodeCompanion.Chat.Messages
local function format_messages(messages)
  local chat_messages = {}
  for _, message in ipairs(messages or {}) do
    table.insert(chat_messages, fmt("## %s\n%s", message.role, message.content))
  end
  return table.concat(chat_messages, "\n")
end

---@param background CodeCompanion.Background
---@param chat CodeCompanion.Chat
---@return table|nil, table|nil -- response, error
function M.request(background, chat)
  if chat.title and chat.title ~= "" then
    return
  end

  -- Send the messages to the LLM to generate a title
  local output, err = background:ask_sync({
    {
      role = "system",
      content = "You are an AI assistant that generates concise and relevant titles for conversations based on their content. The title should be brief, ideally under 10 words, and should accurately reflect the main topic or theme of the conversation. You output only the title without any additional text and formatting",
    },
    {
      role = "user",
      content = fmt(
        [[Generate a concise and relevant title for the following conversation:\n\n%s]],
        format_messages(chat.messages)
      ),
    },
  }, {
    stream = false,
    silent = true,
  })

  print(vim.inspect(output))

  if err then
    return nil, err
  end

  -- Parse the output and extract the title
  local title = output and output.content
  if title then
    -- Clean up the output
    title = title:gsub("^[\"']", ""):gsub("[\"']$", ""):gsub("^%s*", ""):gsub("%s*$", "")

    chat.title = title
    return title, nil
  end

  return nil, { message = "No title generated" }
end

return M
