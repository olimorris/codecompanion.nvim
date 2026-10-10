local config = require("codecompanion.config")
local files_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local fmt = string.format

---@class CodeCompanion.SlashCommand.FileFromUrl: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---@return nil
function SlashCommand:execute()
  vim.ui.input({ prompt = "Enter the URL: " }, function(url)
    url = vim.trim(url or "")
    if url == "" then
      return
    end
    return self:output(url)
  end)
end

---Download the URL and add it to the chat buffer, handing webpages to the fetch slash command
---@param url string
---@return nil
function SlashCommand:output(url)
  utils.notify(fmt("Downloading `%s`", url))

  files_utils.download(url, {
    callback = function(err, file)
      if err then
        return log:error(err)
      end

      if file.mimetype == "text/html" then
        return require("codecompanion.interactions.chat.slash_commands.builtin.fetch")
          .new({ Chat = self.Chat, config = config.interactions.chat.slash_commands.fetch })
          :output(url)
      end

      return require("codecompanion.interactions.shared.slash_commands.file")
        .new({ Chat = self.Chat, config = self.config })
        :output({ path = file.path, id = url, name = (url:gsub("[?#].*$", "")), mimetype = file.mimetype })
    end,
  })
end

return SlashCommand
