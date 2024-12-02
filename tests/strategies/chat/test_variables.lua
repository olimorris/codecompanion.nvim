local h = require("tests.helpers")

describe("Variables", function()
  local chat
  local vars

  before_each(function()
    local Chat = require("codecompanion.strategies.chat")
    local Variables = require("codecompanion.strategies.chat.variables")

    local codecompanion = require("codecompanion")
    local config = require("codecompanion.config")

    -- mock dependencies
    config.strategies = {
      chat = {
        roles = {
          llm = "CodeCompanion",
          user = "Me",
        },
        variables = {
          ["foo"] = {
            callback = "tests.strategies.chat.variables.foo",
            description = "foo",
          },
          ["bar"] = {
            callback = "tests.strategies.chat.variables.bar",
            description = "bar",
            opts = {
              has_params = true,
            },
          },
          ["baz"] = {
            callback = "tests.strategies.chat.variables.baz",
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

    codecompanion.setup(config)

    chat = Chat.new({ adapter = "openai", context = { bufnr = 0 } })
    vars = Variables.new()
  end)

  describe(":parse", function()
    it("should parse a message with a variable", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#foo what does this do?",
      })
      local result = vars:parse(chat, chat.messages[#chat.messages])

      h.eq(true, result)

      local message = chat.messages[#chat.messages]
      h.eq("foo", message.content)
    end)

    it("should return nil if no variable is found", function()
      table.insert(chat.messages, {
        role = "user",
        content = "what does this do?",
      })
      local result = vars:parse(chat, chat.messages[#chat.messages])

      h.eq(false, result)
    end)

    it("should parse a message with a variable and string params", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#bar:baz Can you parse this variable?",
      })
      vars:parse(chat, chat.messages[#chat.messages])

      local message = chat.messages[#chat.messages]
      h.eq("bar baz", message.content)
    end)

    it("should parse a message with a variable and numerical params", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#bar:100-200 Can you parse this variable?",
      })
      vars:parse(chat, chat.messages[#chat.messages])

      local message = chat.messages[#chat.messages]
      h.eq("bar 100-200", message.content)
    end)

    it("should parse a message with a variable and ignore params if they're not enabled", function()
      table.insert(chat.messages, {
        role = "user",
        content = "#baz:qux Can you parse this variable?",
      })
      vars:parse(chat, chat.messages[#chat.messages])

      local message = chat.messages[#chat.messages]
      h.eq("baz", message.content)
    end)

    describe(":replace", function()
      it("should replace the variable in the message", function()
        local message = "#foo #bar replace this var"
        local result = vars:replace(message, "foo")
        h.eq("replace this var", result)
      end)
    end)
  end)
end)
