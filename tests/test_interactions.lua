local mock = require("luassert.mock")

describe("Interactions", function()
  local chat_mock
  local inline_mock

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
    interactions = {
      chat = { adapter = "test_adapter" },
      inline = { adapter = "test_adapter" },
    },
  })

  before_each(function()
    chat_mock = mock(require("codecompanion.interactions.chat"), true)
    inline_mock = mock(require("codecompanion.interactions.inline"), true)

    inline_mock.new = function()
      return {
        start = inline_mock.start,
      }
    end
  end)

  after_each(function()
    mock.revert(chat_mock)
    mock.revert(inline_mock)
  end)

  it("should call chat interaction with a specific adapter", function()
    local context = { mode = "n" }
    local selected = {
      interaction = "chat",
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
  end)
end)

describe("Chat interaction", function()
  it("messages should be populated when selected with a pre-defined prompt", function()
    local item = {
      name = "Explain",
      description = "(/explain) Explain how code in a buffer works",
      interaction = "chat",
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
  end)
end)
