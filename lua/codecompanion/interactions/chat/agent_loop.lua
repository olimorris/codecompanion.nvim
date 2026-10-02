local M = {}

---Decide what happens once the LLM's response is in the chat buffer
---@param chat CodeCompanion.Chat
---@param opts? { tool_calls?: table, error?: string }
---@return nil
function M.after_response(chat, opts)
  opts = opts or {}

  if opts.tool_calls then
    return chat.tools:execute(chat, opts.tool_calls)
  end

  chat:checkpoint()

  -- A message queued during the request is submitted now so the LLM sees it
  if chat._btw then
    return chat:submit({ auto_submit = true })
  end

  -- A compaction request ends the turn itself once its summary lands
  if require("codecompanion.interactions.chat.context_management").apply(chat) then
    return
  end

  chat:finish({ error = opts.error })
end

---Send the tools' output back to the LLM
---@param tools CodeCompanion.Tools
---@return nil
function M.after_tools(tools)
  vim.schedule(function()
    tools.chat:submit({
      auto_submit = true,
      callback = function()
        tools:reset({ auto_submit = true })
      end,
    })
  end)
end

return M
