local log = require("codecompanion.utils.log")

---@class CodeCompanion.Chat.UI.Formatters.Base
---@field chat CodeCompanion.Chat
local BaseFormatter = {}
BaseFormatter.__class = "BaseFormatter"

---@param chat CodeCompanion.Chat
function BaseFormatter:new(chat)
  return setmetatable({
    chat = chat,
  }, { __index = self })
end

---Check if this formatter can handle the given data/opts
---@param data table
---@param opts table
---@return boolean
function BaseFormatter:can_handle(data, opts)
  error("Must implement can_handle method")
end

---Get the tag for this formatter
---@return string
function BaseFormatter:get_tag()
  error("Must implement get_tag method")
end

---Format the content into lines
---@param data table
---@param opts table
---@return table lines, table? fold_info
function BaseFormatter:format(data, opts)
  error("Must implement format method")
end

---Safely format content with error handling
---@param data table
---@param opts table
---@return table lines, table? fold_info
function BaseFormatter:safe_format(data, opts)
  local ok, lines, fold_info = pcall(self.format, self, data, opts, self.chat)
  if not ok then
    log:error("[Formatters] Error in %s formatter:\n%s", self.__class or "unknown", lines)
    -- Return minimal safe output
    return { data.content or "Error formatting content" }, nil
  end
  return lines or {}, fold_info
end

return BaseFormatter
