local config = require("codecompanion.config")
local providers = require("codecompanion.helpers.slash_commands.shared.files")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local fmt = string.format

CONSTANTS = {
  NAME = "File",
  PROMPT = "Select a file",
}

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommand
---@param selected table The selected item from the provider { relative_path = string, path = string }
---@return nil
local function output(SlashCommand, selected)
  if not config.opts.send_code and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local ft = file_utils.get_filetype(selected.path)
  local content = file_utils.read(selected.path)

  if content == "" then
    return log:warn("Could not read the file: %s", selected.path)
  end

  local Chat = SlashCommand.Chat
  local relative_path = selected.relative_path or selected[1] or selected.path
  Chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt(
      [[Here is the content from the file `%s`:

```%s
%s
```]],
      relative_path,
      ft,
      content
    ),
  }, { visible = false })
  util.notify(fmt("Added %s's content to the chat", vim.fn.fnamemodify(relative_path, ":t")))
end

---@class CodeCompanion.SlashCommand.File: CodeCompanion.SlashCommand
---@field new fun(args: CodeCompanion.SlashCommand): CodeCompanion.SlashCommand.File
---@field execute fun(self: CodeCompanion.SlashCommand.File)
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
  if self.config.opts and self.config.opts.provider then
    local provider = providers[self.config.opts.provider] --[[@type function]]
    if not provider then
      return log:error("Provider for the file slash command could not found: %s", self.config.opts.provider)
    end
    provider(self, output)
  else
    providers.telescope(self, output)
  end
end

return SlashCommand
