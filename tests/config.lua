local og_config = require("codecompanion.config")
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
      keymaps = og_config.strategies.chat.keymaps,
      tools = {
        ["cmd_runner"] = {
          callback = "strategies.chat.agents.tools.cmd_runner",
          description = "Run shell commands initiated by the LLM",
        },
        ["files"] = {
          callback = "strategies.chat.agents.tools.files",
          description = "Update the file system with the LLM's response",
        },
        ["next_edit_suggestion"] = {
          callback = "strategies.chat.agents.tools.next_edit_suggestion",
          description = "Suggest and jump to the next position to edit",
        },
        ["insert_edit_into_file"] = {
          callback = "strategies.chat.agents.tools.insert_edit_into_file",
          description = "Insert code into an existing file",
          opts = {
            patching_algorithm = "strategies.chat.agents.tools.helpers.patch",
          },
        },
        ["create_file"] = {
          callback = "strategies.chat.agents.tools.create_file",
          description = "Create a file in the current working directory",
        },
        ["file_search"] = {
          callback = "strategies.chat.agents.tools.file_search",
          description = "Search for files in the current working directory by glob pattern",
          opts = {
            max_results = 500,
          },
        },
        ["grep_search"] = {
          callback = "strategies.chat.agents.tools.grep_search",
          description = "Search for text in the current working directory",
        },
        ["read_file"] = {
          callback = "strategies.chat.agents.tools.read_file",
          description = "Read a file in the current working directory",
        },
        ["weather"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/weather.lua",
          description = "Get the latest weather",
        },
        ["func"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func.lua",
          description = "Some function tool to test",
        },
        ["func_approval"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_approval.lua",
          description = "Some function tool to test with an approval step",
          opts = {
            requires_approval = true,
          },
        },
        ["func_approval2"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/func_approval2.lua",
          description = "Some function tool to test with an approval step that's a table",
          opts = {
            requires_approval = {
              buffer = true, -- We're not actually testing this. requires_approval being a table triggers the user_approval test
            },
          },
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
        ["cmd_queue_error"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/cmd_queue_error.lua",
          description = "Cmd tool",
        },
        ["mock_cmd_runner"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/mock_cmd_runner.lua",
          description = "Cmd tool",
        },
        -- Add tool with same name as a tool group to verify word boundary matching
        ["tool_group_tool"] = {
          callback = vim.fn.getcwd() .. "/tests/strategies/chat/agents/tools/stubs/tool_group_tool.lua",
          description = "Tool group extended",
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
          ["test_group"] = {
            description = "Test Group",
            system_prompt = "Test group system prompt",
            tools = { "func", "weather" },
            opts = { collapse_tools = true },
          },
          ["test_group2"] = {
            description = "Group to be used for testing references",
            system_prompt = "Individual tools system prompt",
            tools = { "func", "weather" },
            opts = { collapse_tools = false },
          },
          ["remove_group"] = {
            description = "Group to be removed during testing of references",
            system_prompt = "System prompt to be removed",
            tools = { "func", "weather" },
            opts = { collapse_tools = true },
          },
        },
        opts = {
          system_prompt = "My tool system prompt",
          wait_timeout = 3000,
          folds = {
            enabled = false,
            failure_words = {
              "error",
              "failed",
              "invalid",
            },
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
        -- Add test variables to verify word boundary matching
        ["foo://10-20-30:40"] = {
          callback = "tests.strategies.chat.variables.foo_special",
          description = "Variable with prefix starting with 'foo' and with special chars",
        },
        ["bar"] = {
          callback = "tests.strategies.chat.variables.bar",
          description = "bar",
          opts = {
            has_params = true,
          },
        },
        ["screenshot://screenshot-2025-05-21T11-17-45.440Z"] = {
          callback = "tests.strategies.chat.variables.screenshot",
          description = "Screenshot",
        },
        ["baz"] = {
          callback = "tests.strategies.chat.variables.baz",
          description = "baz",
        },
      },
      slash_commands = {
        ["buffer"] = {
          callback = "strategies.chat.slash_commands.buffer",
          description = "Insert open buffers",
          keymaps = {
            modes = {
              i = "<C-b>",
              n = { "<C-b>", "gb" },
            },
          },
          opts = {
            contains_code = true,
            provider = "default",
          },
        },
        ["fetch"] = {
          callback = "strategies.chat.slash_commands.fetch",
          description = "Insert URL contents",
          opts = {
            adapter = "jina", -- jina|tavily
            cache_path = vim.fn.stdpath("data") .. "/codecompanion/urls",
            provider = "default",
          },
        },
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
      opts = {
        blank_prompt = "",
      },
    },
    inline = {
      adapter = "test_adapter",
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
    ["Demo"] = {
      strategy = "chat",
      description = "Demo prompt",
      opts = {
        short_name = "demo",
      },
      prompts = {
        {
          role = "system",
          content = "This is some system message",
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          content = "Hi",
        },
        {
          role = "llm",
          content = "What can I do?\n",
        },
        {
          role = "user",
          content = "",
        },
      },
    },
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
        buffer_pin = " ",
        buffer_watch = "👀 ",
        tool_success = "!!",
        tool_failure = "xx",
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
      show_tools_processing = false, -- Show the loading message when tools are being executed?
    },
    diff = { enabled = false },
    icons = {
      loading = " ",
      warning = " ",
    },
  },
  opts = {
    system_prompt = "default system prompt",
  },
}
