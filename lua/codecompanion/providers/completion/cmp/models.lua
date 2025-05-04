local source = {}

---@param config table
function source.new(config)
  return setmetatable({
    config = config,
  }, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion" and self.config.display.chat.show_settings
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
    chat:complete_models(callback)
  else
    callback({ items = {}, isIncomplete = false })
  end
end

return source
