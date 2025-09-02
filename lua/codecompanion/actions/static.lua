local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

local function send_code(context)
  local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

  return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
end

return {
  -- Chat
  {
    name = "Chat",
    strategy = "chat",
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
            return send_code(context)
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
    strategy = " ",
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
      items = function()
        local loaded_chats = codecompanion.buf_get_chat()
        local open_chats = {}

        for _, data in ipairs(loaded_chats) do
          table.insert(open_chats, {
            name = data.name,
            strategy = "chat",
            description = data.description,
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
    name = "Chat with memory ...",
    strategy = " ",
    description = "Add memory to your chat",
    opts = {
      index = 3,
      stop_context_insertion = true,
    },
    condition = function()
      return vim.tbl_count(config.memory) > 0
    end,
    picker = {
      prompt = "Select a memory",
      items = function()
        local memory_items = {}
        local exclusions = { "opts" }

        for name, data in pairs(config.memory) do
          if not vim.tbl_contains(exclusions, name) then
            table.insert(memory_items, {
              name = name,
              strategy = "chat",
              description = data.description,
              callback = function(context)
                local memory = require("codecompanion.strategies.chat.memory")
                  .init({
                    name = name,
                    rules = data.rules,
                    role = data.role,
                    opts = config.memory.opts,
                  })
                  :make()

                codecompanion.chat_with_memory({
                  memory = memory,
                  context = context,
                })
              end,
            })
          end
        end

        return memory_items
      end,
    },
  },
}
