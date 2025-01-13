local Helpers = {}

Helpers.expect = MiniTest.expect --[[@type function]]
Helpers.eq = MiniTest.expect.equality --[[@type function]]
Helpers.not_eq = MiniTest.expect.no_equality --[[@type function]]

Helpers.get_buf_lines = function(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
end

Helpers.config = {
  strategies = {
    chat = {
      roles = {
        llm = "assistant",
        user = "foo",
      },
      agents = {
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

      slash_commands = {
        ["file"] = {
          callback = "strategies.chat.slash_commands.file",
          description = "Insert a file",
          opts = {
            contains_code = true,
            max_lines = 1000,
            provider = "default", -- default|telescope|mini_pick|fzf_lua
          },
        },
      },
    },
  },
  prompt_library = {
    ["Test References"] = {
      strategy = "chat",
      description = "Add some references",
      opts = {
        index = 1,
        is_default = true,
        is_slash_cmd = false,
        short_name = "test_ref",
        auto_submit = false,
      },
      references = {
        {
          type = "file",
          path = {
            "lua/codecompanion/health.lua",
            "lua/codecompanion/http.lua",
          },
        },
      },
      prompts = {
        {
          role = "foo",
          content = "I need some references",
        },
      },
    },
  },
  opts = {
    system_prompt = "default system prompt",
  },
}

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

  codecompanion.setup(Helpers.config)

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
