local match = require("luassert.match")
local mock = require("luassert.mock")

local codecompanion = require("codecompanion")
codecompanion.setup({
  adapters = {
    test_adapter = function()
      return require("codecompanion.adapters").extend("openai", {
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

    assert.equals("test_adapter", call_args.adapter.name)
    assert.equals("custom_model", call_args.adapter.schema.model.default)
  end)
end)

describe("Chat Strategy", function()
  it("messages should be populated when selected with a pre-defined prompt", function()
    local item = {
      name = "Explain",
      description = "(/explain) Explain how code in a buffer works",
      strategy = "chat",
      opts = {
        auto_submit = true,
        default_prompt = true,
        stop_context_insertion = true,
        user_prompt = false,
      },
      prompts = {
        {
          role = "system",
          content = "My system prompt",
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          content = "My user prompt",
          opts = {
            contains_code = true,
          },
        },
      },
    }
    local Strategy = require("codecompanion.strategies")
      .new({
        context = { bufnr = 1, filetype = "lua", mode = "n" },
        selected = item,
      })
      :start(item.strategy)

    local messages = Strategy:get_messages()

    assert.equals("system", messages[#messages - 1].role)
    assert.equals("My system prompt", messages[#messages - 1].content)

    assert.equals("user", messages[#messages].role)
    assert.equals("My user prompt", messages[#messages].content)
  end)
end)
