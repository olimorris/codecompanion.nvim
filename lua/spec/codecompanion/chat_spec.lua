local assert = require("luassert")
local mock = require("luassert.mock")

local codecompanion = require("codecompanion")

local Chat
local adapter = {
  name = "TestAdapter",
  url = "https://api.openai.com/v1/chat/completions",
  roles = {
    llm = "assistant",
    user = "user",
  },
  headers = {
    content_type = "application/json",
  },
  parameters = {
    stream = true,
  },
  handlers = {
    form_parameters = function()
      return {}
    end,
    form_messages = function()
      return {}
    end,
    is_complete = function()
      return false
    end,
  },
  schema = {
    model = {
      default = "gpt-3.5-turbo",
    },
  },
}

describe("Chat", function()
  before_each(function()
    package.loaded["codecompanion.strategies.chat.tools.cmd_runner"] = {
      schema = {},
      system_prompt = function(schema)
        return "baz"
      end,
    }

    codecompanion.setup({
      strategies = {
        chat = {
          roles = {
            llm = "assistant",
            user = "foo",
          },
          variables = {
            ["foo"] = {
              callback = "spec.codecompanion.strategies.chat.variables.foo",
              description = "foo",
            },
          },
        },
        agent = {
          adapter = "openai",
          tools = {
            ["code_runner"] = {
              callback = "tools.code_runner",
              description = "Agent to run code generated by the LLM",
            },
            opts = {
              system_prompt = "bar",
            },
          },
        },
      },
      opts = {
        system_prompt = "foo",
      },
    })

    Chat = require("codecompanion.strategies.chat").new({
      context = { bufnr = 1, filetype = "lua" },
      adapter = require("codecompanion.adapters").extend(adapter),
    })
  end)

  describe("messages", function()
    it("system prompt is added first", function()
      assert.are.same("system", Chat.messages[1].role)
      assert.are.same("foo", Chat.messages[1].content)
    end)

    it("buffer variables are handled", function()
      table.insert(Chat.messages, { role = "user", content = "#foo what does this file do?" })

      local message = Chat.messages[#Chat.messages]
      if Chat.variables:parse(Chat, message) then
        message.content = Chat.variables:replace(message.content)
      end

      -- Variable is inserted as its own new message at the end
      local message = Chat.messages[#Chat.messages]
      assert.are.same("foo", message.content)
      assert.are.same(false, message.opts.visible)
      assert.are.same("variable", message.opts.tag)
    end)
  end)
end)