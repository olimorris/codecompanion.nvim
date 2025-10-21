# The Chat Buffer

The chat buffer is a Neovim buffer which allows a user to interact with an LLM. The buffer is formatted as Markdown with a user's content residing under a H2 header. The user types their message, saves the buffer and the plugin then uses Tree-sitter to parse the buffer, extracting the contents and sending to an adapter which connects to the user's chosen LLM. The response back from the LLM is streamed into the buffer under another H2 header. The user is then free to respond back to the LLM.

The file below is the entry point for the chat strategy. All methods directly relating to the chat buffer reside here.

@./lua/codecompanion/strategies/chat/init.lua

## Message Stack

Messages in the chat buffer are lua table objects as seen. They contain the role of the message (user, assistant, system), the content of the message, and any additional metadata such as visibility and sometimes type. The latter are important when data is being written to the buffer with `add_buf_message` as they allow the chat ui builder pattern to determine the type of message that it's receiving and therefore determine how to format it. In the example shared in below, you can see how a user has prompted the LLM and the LLM's response:

```lua
{ {
    _meta = {
      cycle = 1,
      id = 708950413,
      tag = "system_prompt_from_config",
    },
    opts = {
      visible = false
    },
    role = "system"
    content = "A system prompt",
  }, {
    _meta = {
      cycle = 1,
      id = 533315931,
      sent = true
    },
    opts = {
      visible = true
    },
    role = "user"
    content = "Are you working?",
  }, {
    _meta = {
      cycle = 1,
      id = 1141409506,
    },
    opts = {
      visible = true
    },
    role = "llm"
    content = "Yes, I am active and ready to assist you with programming tasks, code explanations, reviews, or Neovim-related questions. What would you like to do next?",
  } }
```
