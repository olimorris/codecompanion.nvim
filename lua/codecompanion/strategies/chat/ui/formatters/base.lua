local log = require("codecompanion.utils.log")

---@class CodeCompanion.Chat.UI.Formatters.Base
---@field chat CodeCompanion.Chat
---@field is_new_response boolean
---@field last_tag? string
---@field __class string
local BaseFormatter = {}
BaseFormatter.__class = "BaseFormatter"

---@class CodeCompanion.Chat.UI.Formatters.BaseArgs
---@field chat CodeCompanion.Chat
---@field is_new_response boolean
---@field last_tag? string

---@param chat CodeCompanion.Chat
function BaseFormatter:new(chat)
  if not chat then
    error("BaseFormatter:new() called with nil chat")
  end

  return setmetatable({
    chat = chat,
  }, { __index = self })
end

---Check if this formatter can handle the given data/opts
---@param message table
---@param opts table
---@param tags table
---@return boolean
function BaseFormatter:can_handle(message, opts, tags)
  error("Must implement can_handle method")
end

---Get the message type for this formatter
---@return string
function BaseFormatter:get_type()
  error("Must implement get_type method")
end

---Format the content into lines
---@param message table
---@param opts table
---@param state table
---@return table lines, table? fold_info
function BaseFormatter:format(message, opts, state)
  error("Must implement format method")
end

return BaseFormatter
