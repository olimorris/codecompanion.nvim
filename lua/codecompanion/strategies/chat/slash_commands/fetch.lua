local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format

CONSTANTS = {
  NAME = "Fetch",
}

---@class CodeCompanion.SlashCommand.Fetch: CodeCompanion.SlashCommand
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

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local ok, adapter = pcall(require, "codecompanion.adapters.non_llm." .. self.config.opts.adapter)
  if not ok then
    ok, adapter = pcall(loadfile, self.config.opts.provider)
  end

  if type(adapter) == "function" then
    adapter = adapter()
  end

  adapter = adapters.resolve(adapter)
  if not adapter then
    return log:error("Failed to load the provider")
  end

  vim.ui.input({ prompt = "URL" }, function(input)
    if input == "" or not input then
      return
    end

    adapter.env = {
      query = function()
        return input
      end,
    }

    local cb = function(err, data)
      if err then
        return log:error("Error: %s", err)
      end

      if data then
        ok, data = pcall(vim.fn.json_decode, data.body)
        if not ok then
          return log:error("Failed to decode the response")
        end

        if data.code == 200 then
          local content = fmt(
            [[Here is the content from <url>%s</url> that I'm sharing with you:

<content>
%s
</content>]],
            input,
            data.data.text
          )

          self.Chat:add_message({
            role = config.constants.USER_ROLE,
            content = content,
          }, { reference = input, visible = false })

          self.Chat.References:add({
            source = "slash_command",
            name = "fetch",
            id = input,
          })

          return util.notify(fmt("Added the page contents for: %s", input))
        end
        if data.code >= 400 then
          return log:error("Error: %s", data.body.data)
        end
      end
    end

    client
      .new({
        adapter = adapter,
      })
      :request({
        url = input,
      }, { callback = cb })
  end)
end

return SlashCommand
