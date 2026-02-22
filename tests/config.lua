local og_config = require("codecompanion.config")
return {
  constants = {
    LLM_ROLE = "llm",
    USER_ROLE = "user",
    SYSTEM_ROLE = "system",
  },
  adapters = {
    http = {
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
                tools = {
                  call_id = tool_call.id,
                },
                content = output,
                _meta = { tag = tool_call.id },
                opts = { visible = false },
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
    acp = {
      test_acp = {
        name = "test_acp",
        type = "acp",
        command = { "node", "test-agent.js" },
        roles = { user = "user", assistant = "assistant" },
      },
    },
    opts = {
      cmd_timeout = 10e3,
    },
  },
  interactions = {
    background = {},
    chat = {
      adapter = "test_adapter",
      roles = {
        llm = "assistant",
        user = "foo",
      },
      keymaps = og_config.interactions.chat.keymaps,
      tools = {
        ["run_command"] = {
          path = "interactions.chat.tools.builtin.run_command",
          description = "Run shell commands initiated by the LLM",
        },
        ["files"] = {
          path = "interactions.chat.tools.builtin.files",
          description = "Update the file system with the LLM's response",
        },
        ["next_edit_suggestion"] = {
          path = "interactions.chat.tools.builtin.next_edit_suggestion",
          description = "Suggest and jump to the next position to edit",
        },
        ["memory"] = {
          path = "interactions.chat.tools.builtin.memory",
          description = "The memory tool enables Claude to store and retrieve information across conversations through a memory file directory",
        },
        ["insert_edit_into_file"] = {
          path = "interactions.chat.tools.builtin.insert_edit_into_file",
          description = "Robustly edit files with multiple automatic fallback interactions",
          opts = {
            require_approval_before = {
              buffer = false,
              file = false,
            },
            require_confirmation_after = false,
          },
        },
        ["create_file"] = {
          path = "interactions.chat.tools.builtin.create_file",
          description = "Create a file in the current working directory",
        },
        ["delete_file"] = {
          path = "interactions.chat.tools.builtin.delete_file",
          description = "Delete a file in the current working directory",
        },
        ["fetch_webpage"] = {
          path = "interactions.chat.tools.builtin.fetch_webpage",
          description = "Fetches content from a webpage",
          opts = {
            adapter = "jina",
          },
        },
        ["web_search"] = {
          path = "interactions.chat.tools.builtin.web_search",
          description = "Searches the web for a given query",
          opts = {
            adapter = "tavily",
          },
        },
        ["file_search"] = {
          path = "interactions.chat.tools.builtin.file_search",
          description = "Search for files in the current working directory by glob pattern",
          opts = {
            max_results = 500,
          },
        },
        ["grep_search"] = {
          path = "interactions.chat.tools.builtin.grep_search",
          description = "Search for text in the current working directory",
        },
        ["read_file"] = {
          path = "interactions.chat.tools.builtin.read_file",
          description = "Read a file in the current working directory",
        },
        ["ask_questions"] = {
          path = "interactions.chat.tools.builtin.ask_questions",
          description = "Ask the user questions to clarify requirements or validate assumptions",
        },
        ["weather"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/weather.lua",
          description = "Get the latest weather",
        },
        ["weather_with_default"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/weather_with_default.lua",
          description = "Get the latest weather",
        },
        ["func"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func.lua",
          description = "Some function tool to test",
        },
        ["func_approval"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_approval.lua",
          description = "Some function tool to test with an approval step",
          opts = {
            require_approval_before = true,
          },
        },
        ["func_approval2"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_approval2.lua",
          description = "Some function tool to test with an approval step that's a table",
          opts = {
            require_approval_before = {
              buffer = true, -- We're not actually testing this
            },
          },
        },
        ["func_handlers_once"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_handlers_once.lua",
          description = "Some function tool to test",
        },
        ["func2"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func2.lua",
          description = "Some function tool to test",
        },
        ["func_consecutive"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_consecutive.lua",
          description = "Consecutive function tool to test",
        },
        ["func_error"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_error.lua",
          description = "Error function tool to test",
        },
        ["func_return_error"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_return_error.lua",
          description = "Error function tool to test",
        },
        ["func_queue"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_queue.lua",
          description = "Some function tool to test",
        },
        ["func_queue_2"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_queue_2.lua",
          description = "Some function tool to test",
        },
        ["func_async_1"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_async_1.lua",
          description = "Some function tool to test",
        },
        ["func_async_2"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func_async_2.lua",
          description = "Some function tool to test",
        },
        ["cmd"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/cmd.lua",
          description = "Cmd tool",
        },
        ["cmd_consecutive"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/cmd_consecutive.lua",
          description = "Cmd tool",
        },
        ["cmd_error"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/cmd_error.lua",
          description = "Cmd tool",
        },
        ["cmd_queue"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/cmd_queue.lua",
          description = "Cmd tool",
        },
        ["cmd_queue_error"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/cmd_queue_error.lua",
          description = "Cmd tool",
        },
        ["mock_run_command"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/mock_run_command.lua",
          description = "Cmd tool",
        },
        -- Add tool with same name as a tool group to verify word boundary matching
        ["tool_group_tool"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/tool_group_tool.lua",
          description = "Tool group extended",
        },
        ["adapter_tool"] = {
          _adapter_tool = true,
          description = "A mock adapter tool for testing",
        },
        groups = {
          ["senior_dev"] = {
            description = "Tool Group",
            prompt = "I'm giving you access to ${tools} to help me out",
            tools = {
              "func",
              "cmd",
            },
          },
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
            description = "Group to be used for testing context",
            system_prompt = "Individual tools system prompt",
            tools = { "func", "weather" },
            opts = { collapse_tools = false },
          },
          ["remove_group"] = {
            description = "Group to be removed during testing of context",
            system_prompt = "System prompt to be removed",
            tools = { "func", "weather" },
            opts = { collapse_tools = true },
          },
          ["ignore_sys_prompt_group"] = {
            description = "Group that ignores the default system prompt",
            system_prompt = "Custom agent system prompt",
            tools = { "func" },
            opts = { ignore_system_prompt = true },
          },
          ["ignore_tool_sys_prompt_group"] = {
            description = "Group that ignores the tool system prompt",
            system_prompt = "Custom tool agent prompt",
            tools = { "func" },
            opts = { ignore_tool_system_prompt = true },
          },
          ["ignore_both_group"] = {
            description = "Group that ignores both system prompts",
            system_prompt = "Full agent prompt",
            tools = { "func" },
            opts = { ignore_system_prompt = true, ignore_tool_system_prompt = true },
          },
        },
        opts = {
          system_prompt = "My tool system prompt",
          folds = {
            enabled = false,
            failure_words = {
              "error",
              "failed",
              "invalid",
            },
          },
          tool_replacement_message = "the ${tool} tool", -- The message to use when replacing tool names in the chat buffer
        },
      },
      editor_context = {
        ["buffer"] = {
          path = "interactions.chat.editor_context.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            has_params = true,
          },
        },
        ["foo"] = {
          path = "tests.interactions.chat.editor_context.foo",
          description = "foo",
        },
        -- Add test editor_context to verify word boundary matching
        ["foo://10-20-30:40"] = {
          path = "tests.interactions.chat.editor_context.foo_special",
          description = "Variable with prefix starting with 'foo' and with special chars",
        },
        ["bar"] = {
          path = "tests.interactions.chat.editor_context.bar",
          description = "bar",
          opts = {
            has_params = true,
          },
        },
        ["screenshot://screenshot-2025-05-21T11-17-45.440Z"] = {
          path = "tests.interactions.chat.editor_context.screenshot",
          description = "Screenshot",
        },
        ["baz"] = {
          path = "tests.interactions.chat.editor_context.baz",
          description = "baz",
        },
      },
      slash_commands = {
        ["buffer"] = {
          path = "interactions.chat.slash_commands.builtin.buffer",
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
          path = "interactions.chat.slash_commands.builtin.fetch",
          description = "Insert URL contents",
          opts = {
            adapter = "jina", -- jina|tavily
            cache_path = vim.fn.stdpath("data") .. "/codecompanion/urls",
            provider = "default",
          },
        },
        ["file"] = {
          path = "interactions.chat.slash_commands.builtin.file",
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
        debounce = 0,
        wait_timeout = 3000,
        system_prompt = "default system prompt",
      },
    },
    inline = {
      adapter = "test_adapter",
      keymaps = og_config.interactions.inline.keymaps,
      editor_context = {
        ["foo"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/inline/editor_context/foo.lua",
          description = "My foo variable",
        },
        ["bar"] = {
          path = "tests.interactions.inline.editor_context.bar",
          description = "bar",
        },
      },
    },
  },
  mcp = {
    auto_start = true,
    servers = {},
    opts = {
      acp_enabled = true, -- Enable MCP servers with ACP adapters?
      timeout = 10e3,
    },
  },
  prompt_library = {
    ["Demo"] = {
      strategy = "chat",
      description = "Demo prompt",
      opts = {
        alias = "demo",
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
    ["Test Context"] = {
      strategy = "chat",
      description = "Add some context",
      opts = {
        alias = "test_ref",
        is_slash_cmd = false,
        auto_submit = false,
      },
      context = {
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
          content = "I need some context",
        },
      },
    },
  },
  rules = {
    default = {
      description = "Default file selection for CodeCompanion",
      files = {
        "tests/stubs/rules/.rules",
        "tests/stubs/rules/CLAUDE.md",
      },
    },
  },
  display = {
    action_palette = {
      opts = {},
    },
    chat = {
      icons = {
        buffer_sync_all = "󰪴 ",
        buffer_sync_diff = " ",
        tool_success = "!! ",
        tool_failure = "xx ",
      },
      show_context = true,
      fold_context = false,
      show_settings = false,
      window = {
        buflisted = false, -- List the chat buffer in the buffer list?
        sticky = false, -- Chat buffer remains open when switching tabs

        layout = "vertical", -- float|vertical|horizontal|buffer
        full_height = true, -- for vertical layout
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)

        width = 0.5, ---@type number|"auto" using "auto" will allow full_height buffers to act like normal buffers
        height = 0.8,
        border = "single",
        relative = "editor",
        opts = {
          breakindent = true,
          linebreak = true,
          wrap = true,
        },
      },
      floating_window = {},

      intro_message = "", -- Keep this blank or it messes up the screenshot tests
      show_tools_processing = false, -- Show the loading message when tools are being executed?
    },
    diff = {
      enabled = false,
      window = {
        opts = {},
      },
    },
    icons = {
      loading = " ",
      warning = " ",
    },
  },
  opts = {
    triggers = {
      acp_slash_commands = "\\",
      editor_context = "#",
      slash_commands = "/",
      tools = "@",
    },
  },
}
