local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")

local log = require("codecompanion.utils.log")

local fmt = string.format

CONSTANTS = {
  NAME = "Fetch",
}

---@class CodeCompanion.SlashCommandFetch
local SlashCommandFetch = {}

---@class CodeCompanion.SlashCommandFetch
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
function SlashCommandFetch.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommandFetch })

  return self
end

---Execute the slash command
---@return nil
function SlashCommandFetch:execute()
  local ok, adapter = pcall(require, "codecompanion.adapters.non_llm." .. self.config.opts.adapter)
  if not ok then
    ok, adapter = pcall(loadfile, self.config.opts.provider)
  end

  adapter = adapters.resolve(adapter)
  if not adapter then
    return log:error("Failed to load the provider")
  end

  vim.ui.input({ prompt = "URL" }, function(input)
    if input == "" then
      return log:error("URL cannot be empty")
    end

    adapter.env = {
      query = function()
        return input
      end,
    }

    client
      .new({
        adapter = adapter,
      })
      :request({
        url = input,
      }, function(err, chunk)
        if err then
          return log:error("Error: %s", err)
        end

        if chunk then
          ok, chunk = pcall(vim.fn.json_decode, chunk.body)
          if not ok then
            return log:error("Failed to decode the response")
          end

          if chunk.code == 200 then
            local content = fmt(
              [[Here is the content from <url>%s</url> that I'm sharing with you:

<content>
%s
</content>]],
              input,
              chunk.data.text
            )

            self.Chat:add_message({
              role = "user",
              content = content,
            }, { visible = false })

            return vim.notify(fmt("Added the data from %s", input), vim.log.levels.INFO, { title = "CodeCompanion" })
          end
          if chunk.code >= 400 then
            return log:error("Error: %s", chunk.body.data)
          end
        end
      end)
  end)
end

return SlashCommandFetch
