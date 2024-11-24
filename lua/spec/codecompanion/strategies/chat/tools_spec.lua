local Chat = require("codecompanion.strategies.chat")
local Tools = require("codecompanion.strategies.chat.tools")

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

-- Mock dependencies
config.strategies = {
  chat = {
    roles = {
      llm = "CodeCompanion",
      user = "Me",
    },
    variables = {
      ["blank"] = {},
    },
  },
  agent = {
    tools = {
      ["foo"] = {
        callback = "utils.foo",
        description = "Some foo function",
      },
      ["bar"] = {
        callback = "utils.bar",
        description = "Some bar function",
      },
      ["bar_again"] = {
        callback = "utils.bar_again",
        description = "Some bar_again function",
      },
      opts = {
        system_prompt = [[My tool system prompt]],
      },
    },
  },
}

describe("Tools", function()
  local chat
  local tools

  before_each(function()
    codecompanion.setup(config)

    chat = Chat.new({ adapter = "openai", context = { bufnr = 0 } })
    tools = Tools.new({ bufnr = 0 })

    package.loaded["codecompanion.utils.foo"] = {
      system_prompt = function()
        return "foo"
      end,
    }
    package.loaded["codecompanion.utils.bar"] = {
      cmds = {
        function()
          return "bar"
        end,
      },
      system_prompt = function()
        return "bar"
      end,
    }
    package.loaded["codecompanion.utils.bar_again"] = {
      system_prompt = function()
        return "baz"
      end,
    }
  end)

  describe(":parse", function()
    it("should parse a message with a tool", function()
      table.insert(chat.messages, {
        role = "user",
        content = "@foo do some stuff",
      })
      tools:parse(chat, chat.messages[#chat.messages])
      local messages = chat.messages

      assert.equals("My tool system prompt", messages[#messages - 1].content)
      assert.equals("foo", messages[#messages].content)
    end)
  end)

  describe(":replace", function()
    it("should replace the tool in the message", function()
      local message = "@foo replace this tool"
      local result = tools:replace(message, "foo")
      assert.equals("replace this tool", result)
    end)
  end)
end)
