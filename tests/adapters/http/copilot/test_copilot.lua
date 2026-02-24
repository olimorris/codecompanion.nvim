local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

local copilot_models = {
  ["claude-3.5-sonnet"] = {
    endpoint = "completions",
    formatted_name = "Claude Sonnet 3.5",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Anthropic",
  },
  ["claude-3.7-sonnet"] = {
    endpoint = "completions",
    formatted_name = "Claude Sonnet 3.7",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Anthropic",
  },
  ["claude-3.7-sonnet-thought"] = {
    endpoint = "completions",
    formatted_name = "Claude Sonnet 3.7 Thinking",
    opts = {
      can_stream = true,
      has_vision = true,
    },
    vendor = "Anthropic",
  },
  ["claude-sonnet-4"] = {
    endpoint = "completions",
    formatted_name = "Claude Sonnet 4",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Anthropic",
  },
  ["claude-sonnet-4.5"] = {
    endpoint = "completions",
    formatted_name = "Claude Sonnet 4.5 (Preview)",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Anthropic",
  },
  ["gemini-2.0-flash-001"] = {
    endpoint = "completions",
    formatted_name = "Gemini 2.0 Flash",
    opts = {
      can_stream = true,
      has_vision = true,
    },
    vendor = "Google",
  },
  ["gemini-2.5-pro"] = {
    endpoint = "completions",
    formatted_name = "Gemini 2.5 Pro",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Google",
  },
  ["gpt-4.1"] = {
    endpoint = "completions",
    formatted_name = "GPT-4.1",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Azure OpenAI",
  },
  ["gpt-4o"] = {
    endpoint = "completions",
    formatted_name = "GPT-4o",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Azure OpenAI",
  },
  ["gpt-5"] = {
    endpoint = "completions",
    formatted_name = "GPT-5",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Azure OpenAI",
  },
  ["gpt-5-codex"] = {
    endpoint = "responses",
    formatted_name = "GPT-5-Codex (Preview)",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "OpenAI",
  },
  ["gpt-5-mini"] = {
    endpoint = "completions",
    formatted_name = "GPT-5 mini",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Azure OpenAI",
  },
  ["grok-code-fast-1"] = {
    endpoint = "completions",
    formatted_name = "Grok Code Fast 1 (Preview)",
    opts = {
      can_stream = true,
      can_use_tools = true,
    },
    vendor = "xAI",
  },
  ["o3-mini"] = {
    endpoint = "completions",
    formatted_name = "o3-mini",
    opts = {
      can_stream = true,
      can_use_tools = true,
    },
    vendor = "Azure OpenAI",
  },
  ["o4-mini"] = {
    endpoint = "completions",
    formatted_name = "o4-mini (Preview)",
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
    vendor = "Azure OpenAI",
  },
}

local _original_choices
local _original_token_fetch

T["Copilot adapter"] = new_set({
  hooks = {
    pre_case = function()
      local token = require("codecompanion.adapters.http.copilot.token")
      _original_token_fetch = token.fetch
      token.fetch = function()
        return {
          copilot_token = "test_token_12345",
          endpoints = {
            api = "https://api.githubcopilot.com",
          },
        }
      end

      adapter = require("codecompanion.adapters").resolve("copilot")

      local get_models = require("codecompanion.adapters.http.copilot.get_models")
      _original_choices = get_models.choices
      get_models.choices = function(adapter_arg, opts, provided_token)
        return copilot_models
      end
    end,

    post_case = function()
      if _original_choices then
        local get_models = require("codecompanion.adapters.http.copilot.get_models")
        get_models.choices = _original_choices
        _original_choices = nil
      end
      if _original_token_fetch then
        local token = require("codecompanion.adapters.http.copilot.token")
        token.fetch = _original_token_fetch
        _original_token_fetch = nil
      end
    end,
  },
})

T["Copilot adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({
    messages = {
      {
        content = "Explain Ruby in two words",
        copilot_cache_control = { type = "ephemeral" },
        role = "user",
      },
    },
  }, adapter.handlers.form_messages(adapter, messages))
end

T["Copilot adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Copilot adapter"]["forms reasoning output"] = function()
  local messages = {
    {
      content = "Content 1\n",
    },
    {
      content = "Content 2\n",
    },
    {
      content = "Content 3\n",
    },
    {
      opaque = "gj5HGhYVIOT",
    },
  }

  local form_reasoning = adapter.handlers.form_reasoning(adapter, messages)

  h.eq("Content 1\nContent 2\nContent 3\n", form_reasoning.content)
  h.eq("gj5HGhYVIOT", form_reasoning.opaque)
end

T["Copilot adapter"]["Streaming"] = new_set()

T["Copilot adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("**Elegant simplicity.**", output)
end

T["Copilot adapter"]["Streaming"]["can handle quota exceeded"] = function()
  local output = ""
  local status = ""
  local lines = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_quota_exceeded.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    status = chat_output and chat_output.status
    if chat_output and chat_output.output then
      output = output .. chat_output.output
    end
  end

  h.eq("error", status)
  h.expect_starts_with("Your Copilot quota", output)
end

T["Copilot adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"location": "London, UK", "units": "celsius"}',
        name = "weather",
      },
      id = "tooluse_ZnSMh7lhSxWDIuVBKd_vLg",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

T["Copilot adapter"]["Streaming"]["stores reasoning_opaque in extra"] = function()
  local lines = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_tools_streaming_reasoning.txt")

  local output = {}
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output then
      table.insert(output, adapter.handlers.parse_message_meta(adapter, chat_output))
    end
  end

  h.expect_starts_with("lgxMQq0m/J6cVjsaH8bbfhxHtAvK4Y", output[#output].output.reasoning.opaque)
end

T["Copilot adapter"]["Streaming"]["can send reasoning opaque back in messages"] = function()
  local input = {
    {
      content = "Search for quotes.lua",
      role = "user",
    },
    {
      content = "LLM's response here",
      reasoning = {
        content = "Some reasoning here",
        opaque = "SzZZSfDxyWB",
      },
      role = "llm",
    },
    {
      role = "llm",
      tools = {
        calls = {
          {
            _index = 0,
            ["function"] = {
              arguments = '{"dryRun":false,"edits":[{"newText":"    \\"The only limit to our realization of tomorrow will be our doubts of today. - Franklin D. Roosevelt\\",\\n    \\"Talk is cheap. Show me the code. - Linus Torvalds\\",\\n  }","oldText":"    \\"The only limit to our realization of tomorrow will be our doubts of today. - Franklin D. Roosevelt\\",\\n  }","replaceAll":false}],"explanation":"Adding a new quote by Linus Torvalds to the end of the list in quotes.lua.","filepath":"quotes.lua","mode":"append"}',
              name = "insert_edit_into_file",
            },
            id = "call_MHxYMWV1QmRVTng0Znd2b0tyM0Y",
            type = "function",
          },
        },
      },
    },
  }

  local expected = {
    {
      content = "Search for quotes.lua",
      copilot_cache_control = { type = "ephemeral" },
      role = "user",
    },
    {
      content = "LLM's response here",
      copilot_cache_control = { type = "ephemeral" },
      role = "llm",
      reasoning_opaque = "SzZZSfDxyWB",
      reasoning_text = "Some reasoning here",
      tool_calls = {
        {
          ["function"] = {
            arguments = '{"dryRun":false,"edits":[{"newText":"    \\"The only limit to our realization of tomorrow will be our doubts of today. - Franklin D. Roosevelt\\",\\n    \\"Talk is cheap. Show me the code. - Linus Torvalds\\",\\n  }","oldText":"    \\"The only limit to our realization of tomorrow will be our doubts of today. - Franklin D. Roosevelt\\",\\n  }","replaceAll":false}],"explanation":"Adding a new quote by Linus Torvalds to the end of the list in quotes.lua.","filepath":"quotes.lua","mode":"append"}',
            name = "insert_edit_into_file",
          },
          id = "call_MHxYMWV1QmRVTng0Znd2b0tyM0Y",
          type = "function",
        },
      },
    },
  }

  local output = adapter.handlers.form_messages(adapter, input)

  h.eq({ messages = expected }, output)
end

T["Copilot adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("copilot", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Copilot adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    "**Dynamic elegance.**\\n\\nWhat specific aspect of Ruby would you like to explore further?",
    adapter.handlers.chat_output(adapter, json).output.content
  )
end

T["Copilot adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location":"London, UK","units":"celsius"}',
        name = "weather",
      },
      id = "tooluse_0QuujwyeSCGpbfteXu-sHw",
      type = "function",
    },
  }
  h.eq(tool_output, tools)
end

T["Copilot adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/copilot/stubs/copilot_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    "**Dynamic elegance.**\\n\\nWhat specific aspect of Ruby would you like to explore further?",
    adapter.handlers.inline_output(adapter, json).output
  )
end

local token_child = MiniTest.new_child_neovim()

T["Token initialization"] = new_set({
  hooks = {
    pre_case = function()
      token_child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = token_child.stop,
  },
})

T["Token initialization"]["defers token fetching during adapter resolution"] = function()
  token_child.lua([[
      -- Ensure the token state is clean
      local token = require("codecompanion.adapters.http.copilot.token")
      token._oauth_token = nil
      token._copilot_token = nil

      -- Mock token.init to track if it's called
      _G.init_called = false
      local original_init = token.init
      token.init = function(...)
        _G.init_called = true
        return original_init(...)
      end

      local test_adapter = require("codecompanion.adapters").resolve("copilot")

      token.init = original_init
    ]])

  -- Token initialization should not have been called during resolution
  h.eq(token_child.lua_get("_G.init_called"), false)
  h.eq(token_child.lua_get("require('codecompanion.adapters.http.copilot.token')._oauth_token"), vim.NIL)
  h.eq(token_child.lua_get("require('codecompanion.adapters.http.copilot.token')._copilot_token"), vim.NIL)
end

T["Token initialization"]["initializes tokens when api_key is accessed"] = function()
  token_child.lua([[
    local token = require("codecompanion.adapters.http.copilot.token")
    token._oauth_token = nil
    token._copilot_token = nil

    local original_fetch = token.fetch
    token.fetch = function(force_init)
      if force_init or token._oauth_token then
        token._oauth_token = "test_oauth_token"
        token._copilot_token = { token = "test_copilot_token" }
      end
      return {
        oauth_token = token._oauth_token,
        copilot_token = token._copilot_token,
      }
    end

    local test_adapter = require("codecompanion.adapters").resolve("copilot")
    _G.api_key_result = test_adapter.env.api_key()
    _G.oauth_token_result = token._oauth_token
    _G.copilot_token_result = token._copilot_token
    token.fetch = original_fetch
  ]])

  h.eq(token_child.lua_get("_G.api_key_result"), { token = "test_copilot_token" })
  h.eq(token_child.lua_get("_G.oauth_token_result"), "test_oauth_token")
  h.eq(token_child.lua_get("_G.copilot_token_result.token"), "test_copilot_token")
end

T["Token initialization"]["forces token init for synchronous model fetching"] = function()
  token_child.lua([[
      -- Reset token state
      local token = require("codecompanion.adapters.http.copilot.token")
      token._oauth_token = nil
      token._copilot_token = nil

      _G.init_called = false
      local original_init = token.init
      token.init = function()
        _G.init_called = true
        token._oauth_token = "test_oauth_token"
        token._copilot_token = { token = "test_copilot_token", endpoints = { api = "https://api.githubcopilot.com" } }
        return true
      end

      local get_models = require("codecompanion.adapters.http.copilot.get_models")

      -- Mock vim.wait to return immediately
      local original_wait = vim.wait
      vim.wait = function() return true end

      local mock_adapter = { headers = {} }

      -- Synchronous model fetch should force token initialization
      local models = get_models.choices(mock_adapter, { async = false })

      -- Restore originals
      token.init = original_init
      vim.wait = original_wait
    ]])

  -- Token initialization should have been called for sync request
  h.eq(token_child.lua_get("_G.init_called"), true)
end

T["test model selection dialog works with copilot adapter"] = function()
  local child = MiniTest.new_child_neovim()
  child.restart({ "-u", "scripts/minimal_init.lua" })

  local results = child.lua([[
    -- Mock config
    local config = require("codecompanion.config")
    config.adapters = {
      http = {
        opts = { show_model_choices = true }
      }
    }

    -- Mock token module to return tokens when forced
    package.loaded["codecompanion.adapters.http.copilot.token"] = {
      fetch = function()
        return {
          oauth_token = "test_oauth",
          copilot_token = "test_token",
          endpoints = { api = "https://api.githubcopilot.com" }
        }
      end,
    }

    -- Mock get_models to return multiple models when tokens are available
    package.loaded["codecompanion.adapters.http.copilot.get_models"] = {
      choices = function(adapter, opts)
        opts = opts or {}
        if opts.token and opts.token.copilot_token then
          return {
            ["gpt-4.1"] = { formatted_name = "GPT-4.1" },
            ["gpt-4o"] = { formatted_name = "GPT-4o" },
            ["claude-3.5-sonnet"] = { formatted_name = "Claude 3.5 Sonnet" }
          }
        end
        return { ["gpt-4.1"] = { opts = {} } }
      end,
    }

    local copilot = require("codecompanion.adapters.http.copilot")
    local change_adapter = require("codecompanion.interactions.chat.keymaps.change_adapter")

    -- Test that get_models_list returns models for selection dialog
    local models_list = change_adapter.list_http_models(copilot)

    -- Return test results
    return {
      models_list_not_nil = models_list ~= nil,
      models_list_type = type(models_list),
      models_count = models_list and vim.tbl_count(models_list) or 0
    }
  ]])

  child.stop()

  h.eq(results.models_list_not_nil, true)
  h.eq(results.models_list_type, "table")

  -- Should have at least 2 models to show the selection dialog
  if results.models_count < 2 then
    error(string.format("Expected at least 2 models, but got %d", results.models_count))
  end
end

return T
