CONSTANTS = {
  NAME = "Terminal Output",
}

---@class CodeCompanion.SlashCommand.Terminal: CodeCompanion.SlashCommand
---@field new fun(args: CodeCompanion.SlashCommand): CodeCompanion.SlashCommand.Terminal
---@field execute fun(self: CodeCompanion.SlashCommand.Terminal)
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
    return
  end
  local content = vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false)

  local Chat = self.Chat

  Chat:append_to_buf({ content = "[!" .. CONSTANTS.NAME .. "]\n" })
  Chat:append_to_buf({
    content = string.format(
      [[```
Buffer Number: %s
Output:
%s
```]],
      terminal_buf,
      table.concat(content, "\n")
    ),
  })
  Chat:fold_code()
end

return SlashCommand
