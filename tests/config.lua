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
        tools = {
          format_tool_calls = function(self, tools)
            return tools
          end,
          output_response = function(self, tool_call, output)
            return {
              role = "tool",
              tool_call_id = tool_call.id,
              content = output,
              opts = { tag = tool_call.id, visible = false },
            }
          end,
        },
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
      tools = {
        ["cmd_runner"] = {
          callback = "strategies.chat.agents.tools.cmd_runner",
          description = "Run shell commands initiated by the LLM",
        },
        ["editor"] = {
          callback = "strategies.chat.agents.tools.editor",
          description = "Update a buffer with the LLM's response",
        },
        ["weather"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/weather.lua",
          description = "Get the latest weather",
        },
        ["func"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func.lua",
          description = "Some function tool to test",
        },
        ["func_handlers_once"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_handlers_once.lua",
          description = "Some function tool to test",
        },
        ["func2"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func2.lua",
          description = "Some function tool to test",
        },
        ["func_consecutive"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_consecutive.lua",
          description = "Consecutive function tool to test",
        },
        ["func_error"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_error.lua",
          description = "Error function tool to test",
        },
        ["func_return_error"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_return_error.lua",
          description = "Error function tool to test",
        },
        ["func_queue"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_queue.lua",
          description = "Some function tool to test",
        },
        ["func_queue_2"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_queue_2.lua",
          description = "Some function tool to test",
        },
        ["func_async_1"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_async_1.lua",
          description = "Some function tool to test",
        },
        ["func_async_2"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_async_2.lua",
          description = "Some function tool to test",
        },
        ["cmd"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/cmd.lua",
          description = "Cmd tool",
        },
        ["cmd_consecutive"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/cmd_consecutive.lua",
          description = "Cmd tool",
        },
        ["cmd_error"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/cmd_error.lua",
          description = "Cmd tool",
        },
        ["cmd_queue"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/cmd_queue.lua",
          description = "Cmd tool",
        },
        ["mock_cmd_runner"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/mock_cmd_runner.lua",
          description = "Cmd tool",
        },
        groups = {
          ["tool_group"] = {
            description = "Tool Group",
            system_prompt = "My tool group system prompt",
            tools = {
              "func",
              "cmd",
            },
          },
        },
        opts = {
          system_prompt = "My tool system prompt",
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
      intro_message = "", -- Keep this blank or it messes up the screenshot tests
    },
    diff = { enabled = false },
  },
  opts = {
    system_prompt = "default system prompt",
  },
}
