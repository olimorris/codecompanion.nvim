local buf_utils = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")

local M = {}

---Return the contents of the current buffer that the chat was initiated from
---@param chat CodeCompanion.Chat
---@return string
M.buffer = function(chat)
  local output = buf_utils.format_by_id(chat.context.bufnr)
  log:trace("Buffer Variable:\n---\n%s", output)

  return output
end

---Return the open buffers that match the current filetype
---@param chat CodeCompanion.Chat
---@return string
M.buffers = function(chat)
  local output

  local buffers = buf_utils.get_open(chat.context.filetype)
  for _, buffer in ipairs(buffers) do
    output = output .. "\n\n" .. buf_utils.format_by_id(buffer.id)
  end

  return output
end

return M
