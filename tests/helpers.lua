local Helpers = {}

Helpers.expect = MiniTest.expect --[[@type function]]
Helpers.eq = MiniTest.expect.equality --[[@type function]]
Helpers.not_eq = MiniTest.expect.no_equality --[[@type function]]

Helpers.setup_chat_buffer = function()
  local codecompanion = require("codecompanion")

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

  codecompanion.setup({
    strategies = {
      chat = {
        roles = {
          llm = "assistant",
          user = "foo",
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
    },
    opts = {
      system_prompt = "default system prompt",
    },
  })

  local chat = require("codecompanion.strategies.chat").new({
    context = { bufnr = 1, filetype = "lua" },
    adapter = require("codecompanion.adapters").extend(adapter),
  })
  chat.vars = {
    foo = {
      callback = "spec.codecompanion.strategies.chat.variables.foo",
      description = "foo",
    },
  }
  local tools = require("codecompanion.strategies.chat.tools").new({ bufnr = 1 })
  local vars = require("codecompanion.strategies.chat.variables").new()

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

  return chat, tools, vars
end

Helpers.teardown_chat_buffer = function()
  package.loaded["codecompanion.utils.foo"] = nil
  package.loaded["codecompanion.utils.bar"] = nil
  package.loaded["codecompanion.utils.bar_again"] = nil
end

return Helpers
