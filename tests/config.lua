return {
  constants = {
    LLM_ROLE = "llm",
    USER_ROLE = "user",
    SYSTEM_ROLE = "system",
  },
  adapters = {
    test_adapter = {
      name = "test_adapter",
      url = "https://api.openai.com/v1/chat/completions",
      roles = {
        llm = "assistant",
        user = "user",
      },
      opts = {
        stream = true,
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
    },
    opts = {
      allow_insecure = false,
      proxy = nil,
    },
  },
  strategies = {
    chat = {
      adapter = "test_adapter",
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
        ["buffer"] = {
          callback = "strategies.chat.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            has_params = true,
          },
        },
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
    inline = {
      adapter = "foo",
      variables = {
        ["foo"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/inline/variables/foo.lua",
          description = "My foo variable",
        },
        ["bar"] = {
          callback = "tests.strategies.inline.variables.bar",
          description = "bar",
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
  display = {
    chat = {
      icons = {
        pinned_buffer = " ",
        watched_buffer = "👀 ",
      },
      show_references = true,
      show_settings = false,
      window = {
        layout = "vertical", -- float|vertical|horizontal|buffer
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
        border = "single",
        height = 0.8,
        width = 0.45,
        relative = "editor",
        opts = {
          breakindent = true,
          cursorcolumn = false,
          cursorline = false,
          foldcolumn = "0",
          linebreak = true,
          list = false,
          numberwidth = 1,
          signcolumn = "no",
          spell = false,
          wrap = true,
        },
      },
      intro_message = "Hello",
    },
  },
  opts = {
    system_prompt = "default system prompt",
  },
}
