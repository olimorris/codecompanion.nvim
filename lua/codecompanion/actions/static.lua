local codecompanion = require("codecompanion")
local config = require("codecompanion.config")
local rules = require("codecompanion.interactions.chat.rules")
local rules_list = require("codecompanion.interactions.chat.rules.helpers").list()

return {
  -- Chat
  {
    name = "Chat",
    interaction = "chat",
    description = "Create a new chat buffer to converse with an LLM",
    type = nil,
    opts = {
      index = 1,
      stop_context_insertion = true,
    },
    prompts = {
      n = function()
        return codecompanion.chat()
      end,
      v = {
        {
          role = config.constants.SYSTEM_ROLE,
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will give you specific code examples and ask you questions. I want you to advise me with explanations and code examples."
          end,
        },
        {
          role = config.constants.USER_ROLE,
          content = function(context)
            local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
            return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
  -- Open chats
  {
    name = "Open chats ...",
    interaction = " ",
    description = "Your currently open chats",
    opts = {
      index = 2,
      stop_context_insertion = true,
    },
    condition = function()
      return #codecompanion.buf_get_chat() > 0
    end,
    picker = {
      prompt = "Select a chat",
      columns = { "description" },
      items = function()
        local loaded_chats = codecompanion.buf_get_chat()
        local open_chats = {}

        for _, data in ipairs(loaded_chats) do
          table.insert(open_chats, {
            name = data.name,
            interaction = "chat",
            description = data.title or data.description,
            bufnr = data.chat.bufnr,
            callback = function()
              codecompanion.close_last_chat()
              data.chat.ui:open()
            end,
          })
        end

        return open_chats
      end,
    },
  },
  -- Context
  {
    name = "Chat with rules ...",
    interaction = " ",
    description = "Add rules to your chat",
    opts = {
      index = 3,
      stop_context_insertion = true,
    },
    condition = function()
      return vim.tbl_count(rules_list) > 0
    end,
    picker = {
      prompt = "Select a rule",
      items = function()
        local formatted = {}
        for _, item in ipairs(rules_list) do
          table.insert(formatted, {
            name = item.name,
            interaction = "chat",
            description = item.description,
            callback = function(context)
              codecompanion.chat({
                buffer_context = context,
                callbacks = {
                  on_created = function(chat)
                    rules
                      .init({
                        name = item.name,
                        files = item.files,
                        opts = item.opts,
                        parser = item.parser,
                      })
                      :make(chat)
                  end,
                },
              })
            end,
          })
        end
        return formatted
      end,
    },
  },
}
