local match = require("luassert.match")
local mock = require("luassert.mock")

local codecompanion = require("codecompanion")
codecompanion.setup({
  adapters = {
    test_adapter = function()
      return require("codecompanion.adapters").use("ollama", {
        name = "test_adapter",
        schema = {
          model = {
            default = "custom_model",
          },
        },
      })
    end,
    anthropic = "anthropic",
    ollama = "ollama",
    openai = "openai",
  },
  strategies = {
    chat = { adapter = "test_adapter" },
    inline = { adapter = "test_adapter" },
  },
})

describe("Strategies", function()
  local strategies
  local chat_mock
  local inline_mock

  before_each(function()
    chat_mock = mock(require("codecompanion.strategies.chat"), true)
    inline_mock = mock(require("codecompanion.strategies.inline"), true)

    inline_mock.new = function()
      return {
        start = inline_mock.start,
      }
    end

    strategies = require("codecompanion.strategies")
  end)

  after_each(function()
    mock.revert(chat_mock)
    mock.revert(inline_mock)
  end)

  it("should call chat strategy with a specific adapter", function()
    local context = { mode = "n" }
    local selected = {
      strategy = "chat",
      opts = {
        user_prompt = false,
        adapter = {
          name = "test_adapter",
          model = "custom_model",
        },
      },
      prompts = {
        {
          role = "user",
          content = "test content",
        },
      },
    }

    local strategy_instance = strategies.new({ context = context, selected = selected })
    strategy_instance:start("chat")

    assert.stub(chat_mock.new).was_called()
    local call_args = chat_mock.new.calls[1].vals[1]

    assert.equals("test_adapter", call_args.adapter.args.name)
    assert.equals("custom_model", call_args.adapter.args.schema.model.default)
  end)

  -- it("should call inline strategy with a specific adapter", function()
  --   local context = { mode = "n" }
  --   local selected = {
  --     strategy = "inline",
  --     opts = {
  --       user_prompt = false,
  --       adapter = {
  --         name = "test_adapter",
  --         model = "custom_model",
  --       },
  --     },
  --     prompts = {
  --       {
  --         role = "user",
  --         content = "test content",
  --       },
  --     },
  --   }
  --
  --   local strategy_instance = strategies.new({ context = context, selected = selected })
  --   strategy_instance:start("inline")
  --
  --   local call = inline_mock.start.calls[1]
  --   local strategy = call.vals[1]
  --
  --   assert.is_not_nil(strategy.adapter, "Adapter should not be nil")
  --   assert.is_not_nil(strategy.adapter.args, "Adapter args should not be nil")
  --   assert.equals("test_adapter", strategy.adapter.args.name)
  --   assert.equals("custom_model", strategy.adapter.args.schema.model.default)
  -- end)
end)
