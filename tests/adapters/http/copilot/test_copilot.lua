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

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Copilot adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests.strategies.chat.tools.catalog.stubs.weather").schema
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
      role = "user",
    },
    {
      content = "LLM's response here",
      role = "llm",
      reasoning_opaque = "SzZZSfDxyWB",
      reasoning_text = "Some reasoning here",
      tools_calls = {
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

return T
