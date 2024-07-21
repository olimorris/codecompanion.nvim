local Chat = require("codecompanion.strategies.chat")
local Variables = require("codecompanion.strategies.chat.variables")

local codecompanion = require("codecompanion")
local config = require("codecompanion").config

-- Mock dependencies
config.strategies = {
  chat = {
    variables = {
      ["test"] = {
        callback = "utils.test.func",
        description = "Share the current buffer with the LLM",
      },
      ["test_again"] = {
        callback = "utils.test.func",
        description = "Share all current open buffers with the LLM",
      },
    },
  },
}

describe("Variables", function()
  local vars
  local chat

  before_each(function()
    codecompanion.setup()
    vars = Variables.new()

    package.loaded["codecompanion.utils.test"] = {
      func = function()
        return "result"
      end,
    }
  end)

  describe(":parse", function()
    it("should parse a message with a variable", function()
      local result = vars:parse(chat, "#test What does this code do?", 1)
      assert.is_not_nil(result)
      assert.equals("test", result.var)
      assert.equals(1, result.index)
    end)

    it("should return nil if no variable is found", function()
      local result = vars:parse(chat, "no variable here", 1)
      assert.is_nil(result)
    end)
  end)

  describe(":replace", function()
    it("should replace a variable in the message", function()
      local message = "#test replace this variable"
      local result = vars:replace(message, { var = "test" })
      assert.equals("replace this variable", result)
    end)
  end)

  it("should resolve a built-in callback", function()
    local result = vars:parse(chat, "#test what is happening?", 1)
    assert.equals("result", result.content)
  end)
end)
