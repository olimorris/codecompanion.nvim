local helpers = require("codecompanion.helpers.buffers")

local M = {}

---Return the contents of the current buffer that the chat was initiated from
---@param chat CodeCompanion.Chat
---@return string
M.buffer = function(chat)
  return helpers.format(helpers.get_buffer_content(chat.context.bufnr), chat.context.filetype)
end

---Return the open buffers that match the current filetype
---@param chat CodeCompanion.Chat
---@return string
M.buffers = function(chat)
  return helpers.format(helpers.get_opened_content(chat.context.filetype), chat.context.filetype)
end

return M
