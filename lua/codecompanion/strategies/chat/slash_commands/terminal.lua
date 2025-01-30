local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local CONSTANTS = {
  NAME = "Terminal Output",
}

---@class CodeCompanion.SlashCommand.Terminal: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommand
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local terminal_buf = _G.codecompanion_last_terminal
  if not terminal_buf then
    util.notify("No recent terminal buffer found.", vim.log.levels.WARN)
    return
  end
  local ok, content = pcall(function()
    return vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false)
  end)

  if not ok then
    return log:error("Failed to get terminal output")
  end

  local Chat = self.Chat
  Chat:add_message({
    role = config.constants.USER_ROLE,
    content = string.format(
      [[Here is the terminal output for buffer number `%s`:

<terminal>
%s
</terminal>]],
      terminal_buf,
      table.concat(content, "\n")
    ),
  }, { visible = false })
  util.notify("Terminal output added to chat")
end

return SlashCommand
