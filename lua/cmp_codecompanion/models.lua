local config = require("codecompanion").config

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion" and config.display.chat.show_settings
end

source.get_position_encoding_kind = function()
  return "utf-8"
end

function source:get_keyword_pattern()
  return [[\w*]]
end

function source:complete(request, callback)
  local chat = require("codecompanion").buf_get_chat(0)
  if chat then
    chat:complete(request, callback)
  else
    callback({ items = {}, isIncomplete = false })
  end
end

return source
