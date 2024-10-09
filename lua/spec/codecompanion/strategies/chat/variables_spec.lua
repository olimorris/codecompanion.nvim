local Chat = require("codecompanion.strategies.chat")
local Variables = require("codecompanion.strategies.chat.variables")

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

-- mock dependencies
config.strategies = {
  chat = {
    variables = {
      ["foo"] = {
        callback = "utils.foo",
        description = "foo",
      },
      ["bar"] = {
        callback = "utils.bar",
        description = "bar",
        opts = {
          has_params = true,
        },
      },
      ["baz"] = {
        callback = "utils.baz",
        description = "baz",
      },
    },
  },
  agent = {
    tools = {
      ["blank"] = {},
    },
  },
}

describe("Variables", function()
  local chat
  local vars

  before_each(function()
    codecompanion.setup(config)

    chat = Chat.new({ adapter = "openai", context = { bufnr = 0 } })
    vars = Variables.new()

    package.loaded["codecompanion.utils"] = {
      foo = function(chat, params)
        return "foo"
      end,
      bar = function(chat, params)
        if params then
          return "bar " .. params
        end

        return "bar"
      end,
      baz = function(chat, params)
        if params then
          return "baz " .. params
        end

        return "baz"
      end,
    }
  end)

  describe(":parse", function()
    it("should parse a message with a variable", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#foo what does this do?",
      })
      local result = vars:parse(chat, chat.messages[#chat.messages])

      assert.equals(true, result)

      local message = chat.messages[#chat.messages]
      assert.equals("foo", message.content)
    end)

    it("should return nil if no variable is found", function()
      table.insert(chat.messages, {
        role = "user",
        content = "what does this do?",
      })
      local result = vars:parse(chat, chat.messages[#chat.messages])

      assert.equals(false, result)
    end)

    it("should parse a message with a variable and string params", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#bar:baz Can you parse this variable?",
      })
      vars:parse(chat, chat.messages[#chat.messages])

      local message = chat.messages[#chat.messages]
      assert.equals("bar baz", message.content)
    end)

    it("should parse a message with a variable and numerical params", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#bar:100-200 Can you parse this variable?",
      })
      vars:parse(chat, chat.messages[#chat.messages])

      local message = chat.messages[#chat.messages]
      assert.equals("bar 100-200", message.content)
    end)

    it("should parse a message with a variable and ignore params if they're not enabled", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#baz:qux Can you parse this variable?",
      })
      vars:parse(chat, chat.messages[#chat.messages])

      local message = chat.messages[#chat.messages]
      assert.equals("baz", message.content)
    end)

    describe(":replace", function()
      it("should replace the variable in the message", function()
        local message = "#foo #bar replace this var"
        local result = vars:replace(message, "foo")
        assert.equals("replace this var", result)
      end)
    end)
  end)
end)
