local Chat = require("codecompanion.strategies.chat")
local Variables = require("codecompanion.strategies.chat.variables")

local codecompanion = require("codecompanion")
local config = require("codecompanion").config

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
}

describe("Variables", function()
  local chat
  local vars

  before_each(function()
    codecompanion.setup()
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
      local result = vars:parse(chat, "#foo What does this code do?")
      assert.is_not_nil(result)
      assert.equals("foo", result.content)
    end)

    it("should return nil if no variable is found", function()
      local result = vars:parse(chat, "no variable here", 1)
      assert.is_nil(result)
    end)

    it("should parse a message with a variable and string params", function()
      local result = vars:parse(chat, "#bar:baz Can you parse this variable?", 1)
      assert.equals("bar baz", result.content)
    end)
    it("should parse a message with a variable and numerical params", function()
      local result = vars:parse(chat, "#bar:100-200 Can you parse this variable?", 1)
      assert.equals("bar 100-200", result.content)
    end)
    it("should parse a message with a variable and ignore params if they're not enabled", function()
      local result = vars:parse(chat, "#baz:qux Can you parse this variable?", 1)
      assert.equals("baz", result.content)
    end)
  end)

  describe(":replace", function()
    it("should replace a variable in the message", function()
      local message = "#foo replace this variable"
      local result = vars:replace(message, { var = "foo" })
      assert.equals("replace this variable", result)
    end)
  end)

  it("should resolve a built-in callback", function()
    local result = vars:parse(chat, "#foo what is happening?", 1)
    assert.equals("foo", result.content)
  end)
end)
