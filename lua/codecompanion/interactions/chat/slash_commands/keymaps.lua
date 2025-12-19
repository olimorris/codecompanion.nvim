local config = require("codecompanion.config")
local slash_commands = require("codecompanion.interactions.chat.slash_commands")

local M = {}

for name, cmd in pairs(config.interactions.chat.slash_commands) do
  M[name] = {
    callback = function(chat)
      return slash_commands.new():execute({ label = name, config = cmd }, chat)
    end,
  }
end

return M
