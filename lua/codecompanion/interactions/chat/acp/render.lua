local config = require("codecompanion.config")
local extract_text = require("codecompanion.acp.prompt_builder").extract_text

local M = {}

---Render the session in the chat buffer
---@param chat CodeCompanion.Chat
---@param updates table[] Collected session update params from session/load
---@return nil
function M.restore_session(chat, updates)
  chat:clear()

  local user_chunks = {}
  local llm_chunks = {}

  local function process_user_chunks()
    if #user_chunks > 0 then
      local text = table.concat(user_chunks)
      chat:add_buf_message({ role = config.constants.USER_ROLE, content = text })
      user_chunks = {}
    end
  end

  local function process_llm_chunks()
    if #llm_chunks > 0 then
      local text = table.concat(llm_chunks)
      chat:add_buf_message(
        { role = config.constants.LLM_ROLE, content = text },
        { type = chat.MESSAGE_TYPES.LLM_MESSAGE }
      )
      llm_chunks = {}
    end
  end

  for _, update in ipairs(updates) do
    local kind = update.sessionUpdate

    if kind == "user_message_chunk" then
      process_llm_chunks()
      local text = extract_text(update.content)
      if text and text ~= "" then
        table.insert(user_chunks, text)
      end
    elseif kind == "agent_message_chunk" then
      process_user_chunks()
      local text = extract_text(update.content)
      if text and text ~= "" then
        table.insert(llm_chunks, text)
      end
    elseif kind == "tool_call" or kind == "tool_call_update" then
      process_user_chunks()
    end
  end

  -- Process any remaining content
  process_user_chunks()
  process_llm_chunks()

  chat:ready_for_input()
end

return M
