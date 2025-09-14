# The Chat Buffer

The chat buffer is a Neovim buffer which allows a user to interact with an LLM. The buffer is formatted as Markdown with a user's content residing under a H2 header. The user types their message, saves the buffer and the plugin then uses Tree-sitter to parse the buffer, extracting the contents and sending to an adapter which connects to the user's chosen LLM. The response back from the LLM is streamed into the buffer under another H2 header. The user is then free to respond back to the LLM.

The file below is the entry point for the chat strategy. All methods directly relating to the chat buffer reside here.

@./lua/codecompanion/strategies/chat/init.lua

## Message Stack

Messages in the chat buffer are lua table objects as seen. They contain the role of the message (user, assistant, system), the content of the message, and any additional metadata such as visibility and sometimes type. The latter are important when data is being written to the buffer with `add_buf_message` as they allow the chat ui builder pattern to determine the type of message that it's receiving and therefore determine how to format it. In the example shared in below, you can see how a user has prompted the LLM and the LLM's response:

```lua
{ {
    content = "You are an AI programming assistant named \"CodeCompanion\", working within the Neovim text editor.\n\nYou can answer general programming questions and perform the following tasks:\n* Answer general programming questions.\n* Explain how the code in a Neovim buffer works.\n* Review the selected code from a Neovim buffer.\n* Generate unit tests for the selected code.\n* Propose fixes for problems in the selected code.\n* Scaffold code for a new workspace.\n* Find relevant code to the user's query.\n* Propose fixes for test failures.\n* Answer questions about Neovim.\n\nFollow the user's requirements carefully and to the letter.\nUse the context and attachments the user provides.\nKeep your answers short and impersonal, especially if the user's context is outside your core tasks.\nAll non-code text responses must be written in the English language.\nUse Markdown formatting in your answers.\nDo not use H1 or H2 markdown headers.\nWhen suggesting code changes or new content, use Markdown code blocks.\nTo start a code block, use 4 backticks.\nAfter the backticks, add the programming language name as the language ID.\nTo close a code block, use 4 backticks on a new line.\nIf the code modifies an existing file or should be placed at a specific location, add a line comment with 'filepath:' and the file path.\nIf you want the user to decide where to place the code, do not add the file path comment.\nIn the code block, use a line comment with '...existing code...' to indicate code that is already present in the file.\nCode block example:\n````languageId\n// filepath: /path/to/file\n// ...existing code...\n{ changed code }\n// ...existing code...\n{ changed code }\n// ...existing code...\n````\nEnsure line comments use the correct syntax for the programming language (e.g. \"#\" for Python, \"--\" for Lua).\nFor code blocks use four backticks to start and end.\nAvoid wrapping the whole response in triple backticks.\nDo not include diff formatting unless explicitly asked.\nDo not include line numbers in code blocks.\n\nWhen given a task:\n1. Think step-by-step and, unless the user requests otherwise or the task is very simple, describe your plan in pseudocode.\n2. When outputting code blocks, ensure only relevant code is included, avoiding any repeating or unrelated code.\n3. End your response with a short suggestion for the next user turn that directly supports continuing the conversation.\n\nAdditional context:\nThe current date is September 13, 2025.\nThe user's Neovim version is 0.12.0.\nThe user is working on a Mac machine. Please respond with system specific commands if applicable.",
    cycle = 1,
    id = 708950413,
    opts = {
      tag = "system_prompt_from_config",
      visible = false
    },
    role = "system"
  }, {
    _meta = {
      sent = true
    },
    content = "Are you working?",
    cycle = 1,
    id = 533315931,
    opts = {
      visible = true
    },
    role = "user"
  }, {
    _meta = {},
    content = "Yes, I am active and ready to assist you with programming tasks, code explanations, reviews, or Neovim-related questions. What would you like to do next?",
    cycle = 1,
    id = 1141409506,
    opts = {
      visible = true
    },
    role = "llm"
  } }
```
