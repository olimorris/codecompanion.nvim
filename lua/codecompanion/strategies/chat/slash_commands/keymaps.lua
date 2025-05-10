local config = require("codecompanion.config")
local slash_commands = require("codecompanion.strategies.chat.slash_commands")

local M = {}

for name, cmd in pairs(config.strategies.chat.slash_commands) do
  M[name] = {
    callback = function(chat)
      return slash_commands.new():execute({ label = name, config = cmd }, chat)
    end,
  }
end

return M
