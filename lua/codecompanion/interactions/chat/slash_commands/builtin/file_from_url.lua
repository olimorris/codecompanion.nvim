local config = require("codecompanion.config")
local files_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local ui_utils = require("codecompanion.utils.ui")

local CONSTANTS = {
  NAMESPACE = "codecompanion_file_from_url",
}

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
  local bufnr = self.Chat.bufnr
  ui_utils.show_buffer_notification(
    bufnr,
    { namespace = CONSTANTS.NAMESPACE, text = "Downloading the file...", main_hl = "Comment" }
  )

  files_utils.download(url, {
    callback = function(err, file)
      ui_utils.clear_notification(bufnr, { namespace = CONSTANTS.NAMESPACE })
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
        :output({ path = file.path, name = url, mimetype = file.mimetype })
    end,
  })
end

return SlashCommand
