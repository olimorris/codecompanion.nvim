return {
  adapters = {
    http = {
      test_adapter = {
        name = "test_adapter",
        url = "http://localhost/v1/chat/completions",
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
    opts = {
      watcher = {
        enabled = true,
        debounce = 500,
      },
    },
    background = {},
    -- Tests submit chats with the cwd inside the real repo, so never snapshot it
    code_review = {
      enabled = false,
      opts = {
        storage_dir = vim.fs.joinpath(vim.fn.tempname(), "codecompanion", "code_review"),
      },
    },
    chat = {
      adapter = "test_adapter",
      roles = {
        llm = "assistant",
        user = "foo",
      },
      tools = {
        ["run_command"] = {
          opts = {
            require_approval_before = false,
            require_cmd_approval = false,
          },
        },
        -- Shares a name with the shipped `files` tool group, so that a tool is
        -- shown to win over a group of the same name
        ["files"] = {
          path = vim.fn.getcwd() .. "/tests/interactions/chat/tools/builtin/stubs/func.lua",
          description = "Some function tool to test",
        },
        ["insert_edit_into_file"] = {
          opts = {
            require_approval_before = {
              buffer = false,
              file = false,
            },
            require_confirmation_after = false,
          },
        },
        ["create_file"] = {
          opts = {
            require_approval_before = false,
            require_confirmation_after = false,
          },
        },
        ["delete_file"] = {
          opts = {
            require_approval_before = false,
          },
        },
        ["grep_search"] = {
          opts = {
            require_approval_before = false,
          },
        },
        ["read_file"] = {
          opts = {
            require_approval_before = false,
          },
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
          -- Keep tool output in the chat buffer; auto-submitting would fire a request to the adapter
          auto_submit_errors = false,
          auto_submit_success = false,
          system_prompt = "My tool system prompt",
          folds = {
            enabled = false,
          },
        },
      },
      slash_commands = {
        ["buffer"] = {
          keymaps = {
            modes = {
              i = "<C-b>",
              n = { "<C-b>", "gb" },
            },
          },
          opts = {
            provider = "default",
          },
        },
        ["fetch"] = {
          opts = {
            provider = "default",
          },
        },
        ["file"] = {
          opts = {
            provider = "default", -- default|telescope|mini_pick|fzf_lua
          },
        },
      },
      opts = {
        debounce = 0,
        wait_timeout = 3000,
        system_prompt = "default system prompt",
      },
    },
    inline = {
      adapter = "test_adapter",
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
    shared = {
      editor_context = {
        ["foo"] = {
          path = "tests.interactions.shared.editor_context.foo",
          description = "foo",
        },
        -- Add test editor_context to verify word boundary matching
        ["foo://10-20-30:40"] = {
          path = "tests.interactions.shared.editor_context.foo_special",
          description = "Variable with prefix starting with 'foo' and with special chars",
        },
        ["bar"] = {
          path = "tests.interactions.shared.editor_context.bar",
          description = "bar",
          opts = {
            has_params = true,
          },
        },
        ["screenshot://screenshot-2025-05-21T11-17-45.440Z"] = {
          path = "tests.interactions.shared.editor_context.screenshot",
          description = "Screenshot",
        },
        ["baz"] = {
          path = "tests.interactions.shared.editor_context.baz",
          description = "baz",
        },
        ["code_review"] = {
          path = "interactions.shared.editor_context.code_review",
          description = "Share your pending code review comments with the LLM",
          opts = {
            contains_code = true,
            replacement = "my comments from the code review, which I've attached",
          },
        },
      },
    },
  },
  mcp = {
    opts = {
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
      files = {
        "tests/stubs/rules/.rules",
        "tests/stubs/rules/CLAUDE.md",
      },
    },
  },
  display = {
    chat = {
      icons = {
        tool_success = "!! ",
        tool_failure = "xx ",
      },
      intro_message = "", -- Keep this blank or it messes up the screenshot tests
    },
    diff = {
      enabled = false,
    },
    icons = {
      loading = " ",
    },
  },
}
