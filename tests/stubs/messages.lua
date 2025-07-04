local messages = {
  {
    content = "You are an AI programming assistant named \"CodeCompanion\". You are currently plugged into the Neovim text editor on a user's machine.\n\nYour core tasks include:\n- Answering general programming questions.\n- Explaining how the code in a Neovim buffer works.\n- Reviewing the selected code from a Neovim buffer.\n- Generating unit tests for the selected code.\n- Proposing fixes for problems in the selected code.\n- Scaffolding code for a new workspace.\n- Finding relevant code to the user's query.\n- Proposing fixes for test failures.\n- Answering questions about Neovim.\n- Running tools.\n\nYou must:\n- Follow the user's requirements carefully and to the letter.\n- Use the context and attachments the user provides.\n- Keep your answers short and impersonal, especially if the user's context is outside your core tasks.\n- Minimize additional prose unless clarification is needed.\n- Use Markdown formatting in your answers.\n- Include the programming language name at the start of each Markdown code block.\n- Do not include line numbers in code blocks.\n- Avoid wrapping the whole response in triple backticks.\n- Only return code that's directly relevant to the task at hand. You may omit code that isn’t necessary for the solution.\n- Avoid using H1, H2 or H3 headers in your responses as these are reserved for the user.\n- Use actual line breaks in your responses; only use \"\\n\" when you want a literal backslash followed by 'n'.\n- All non-code text responses must be written in the English language indicated.\n- Multiple, different tools can be called as part of the same response.\n\nWhen given a task:\n1. Think step-by-step and, unless the user requests otherwise or the task is very simple, describe your plan in detailed pseudocode.\n2. Output the final code in a single code block, ensuring that only relevant code is included.\n3. End your response with a short suggestion for the next user turn that directly supports continuing the conversation.\n4. Provide exactly one complete reply per conversation turn.\n5. If necessary, execute multiple tools in a single turn.",
    cycle = 1,
    id = 126646444,
    opts = {
      tag = "from_config",
      visible = false,
    },
    role = "system",
  },
  {
    content = "Can you search for `add_buf_message` using the grep_search tool?",
    cycle = 1,
    id = 140643692,
    opts = {
      visible = true,
    },
    role = "user",
  },
  {
    cycle = 1,
    id = 1575342054,
    opts = {
      visible = false,
    },
    role = "llm",
    tool_calls = {
      {
        _index = 0,
        ["function"] = {
          arguments = '{"query":"add_buf_message"}',
          name = "grep_search",
        },
        id = "call_8Aoq8io63MloLbV3qPErKwq9",
        type = "function",
      },
    },
  },
  {
    content = "<grepSearchTool>Searched text for `add_buf_message`, 27 results\n```\ncodecompanion-workspace.json:121 \nhelpers.lua:40 tests\nhelpers.lua:97 tests\nhelpers.lua:127 tests\nhelpers.lua:144 tests\ntest_tools_in_chat_buffer.lua:66 tests/adapters\ntest_tools_in_chat_buffer.lua:79 tests/adapters\ntest_references.lua:128 tests/strategies/chat\ntest_references.lua:193 tests/strategies/chat\ntest_references.lua:205 tests/strategies/chat\ntest_references.lua:342 tests/strategies/chat\ntest_chat.lua:105 tests/strategies/chat\ntest_chat.lua:122 tests/strategies/chat\ntest_subscribers.lua:26 tests/strategies/chat\ntest_subscribers.lua:31 tests/strategies/chat\ntest_messages.lua:27 tests/strategies/chat\ntest_tool_output.lua:62 tests/strategies/chat/agents/tools\ninit.lua:105 lua/codecompanion\ninit.lua:65 lua/codecompanion/providers/completion\ninit.lua:206 lua/codecompanion/strategies/chat\ninit.lua:983 lua/codecompanion/strategies/chat\ninit.lua:1174 lua/codecompanion/strategies/chat\ninit.lua:1250 lua/codecompanion/strategies/chat\ninit.lua:1287 lua/codecompanion/strategies/chat\ninit.lua:195 lua/codecompanion/strategies\ninit.lua:331 lua/codecompanion/strategies/chat/agents\nnow.lua:19 lua/codecompanion/strategies/chat/slash_commands\n```\n\nNOTE:\n- The output format is {filename}:{line number} {filepath}.\n- For example:\ninit.lua:335 lua/codecompanion/strategies/chat/agents\nRefers to line 335 of the init.lua file in the lua/codecompanion/strategies/chat/agents path</grepSearchTool>",
    cycle = 1,
    id = 1528635204,
    opts = {
      tag = "tool_output",
      visible = true,
    },
    role = "tool",
    tool_call_id = "call_8Aoq8io63MloLbV3qPErKwq9",
  },
  {
    content = "The search for `add_buf_message` returned 27 results across multiple files, including `helpers.lua`, `init.lua`, and several test files.\n\nWould you like to see the code for a specific occurrence, or do you want a summary of how `add_buf_message` is used throughout the codebase?",
    cycle = 1,
    id = 668750022,
    opts = {
      visible = true,
    },
    role = "llm",
  },
}
