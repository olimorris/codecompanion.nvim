# The Chat Buffer

The chat buffer is a Neovim buffer which allows a user to interact with an LLM. The buffer is formatted as Markdown with a user's content residing under a H2 header. The user types their message, saves the buffer and the plugin then uses Tree-sitter to parse the buffer, extracting the contents and sending to an adapter which connects to the user's chosen LLM. The response back from the LLM is streamed into the buffer under another H2 header. The user is then free to respond back to the LLM.

The file below is the entry point for the chat strategy. All methods directly relating to the chat buffer reside here.

@./lua/codecompanion/interactions/chat/init.lua

## Message Stack

Messages in the chat buffer are lua table objects as seen. They contain the role of the message (user, assistant, system), the content of the message, and any additional metadata such as visibility and sometimes type. The latter are important when data is being written to the buffer with `add_buf_message` as they allow the chat ui builder pattern to determine the type of message that it's receiving and therefore determine how to format it. In the example shared in below, you can see how a user has prompted the LLM and the LLM's response:

```lua
{ {
    _meta = {
      cycle = 1,
      id = 708950413,
      estimated_tokens = 20,
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
      estimated_tokens = 20,
      id = 533315931,
      sent = true
    },
    opts = {
      visible = true
    },
    role = "user"
    content = "Are you working? Sharing a file with you",
  },
 {
    _meta = {
      cycle = 1,
      estimated_tokens = 3556,
      id = 1048633318,
      index = 5,
      sent = true,
      source = "editor_context",
      tag = "file"
    },
    content = "<attachment filepath=\"/Users/Oli/some_path/some_file.lua\">An example file</attachment>",
    context = {
      id = "<file>some_path/some_file.lua</file>",
      path = "/Users/Oli/some_path/some_file.lua",
    },
    opts = {
      visible = false
    },
    role = "user"
  },
  {
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

## Message Tags

Messages may carry a `_meta.tag` value identifying the origin or kind of the message. Tags are how downstream code (adapters, compaction, system prompt management, etc.) recognises and acts on specific message types. The full set of tags is centralised at `lua/codecompanion/interactions/shared/tags.lua` — refer to that module rather than repeating the string literals in code.

| Tag | Set by | Read by |
|---|---|---|
| `buffer` | `shared/slash_commands/buffer.lua`, `shared/editor_context/buffer.lua`, `shared/editor_context/buffers.lua` | `adapters/acp/helpers.lua` |
| `compact_summary` | `chat/context_management/compaction.lua` | `chat/context_management/compaction.lua` (re-run replacement) |
| `diagnostics` | `shared/editor_context/diagnostics.lua` | — |
| `diff` | `shared/editor_context/diff.lua` | — |
| `editor_context` | legacy editor_context emitters | `chat/slash_commands/builtin/compact.lua` |
| `file` | `shared/slash_commands/file.lua` | `adapters/acp/helpers.lua`, `chat/slash_commands/builtin/compact.lua` |
| `from_custom_prompt` | `interactions/init.lua` (custom prompt library entries) | — |
| `image` | `chat/init.lua:add_image_message` | every HTTP adapter, `adapters/acp/helpers.lua`, title generation |
| `messages` | `shared/editor_context/messages.lua` | — |
| `quickfix` | `shared/editor_context/quickfix.lua` | — |
| `rules` | `shared/rules/helpers.lua` | `chat/slash_commands/builtin/compact.lua`, title generation |
| `selection` | `shared/editor_context/selection.lua` | — |
| `system_prompt_from_config` | `chat/init.lua:set_system_prompt` | `chat/tool_registry.lua`, title generation |
| `terminal` | `shared/editor_context/terminal.lua` | — |
| `tool` | `chat/tool_registry.lua` | `chat/tool_registry.lua` (group tear-down) |
| `tool_output` | adapters (via `format_response`) | `chat/ui/init.lua` (rendering spacing) |
| `tool_system_prompt` | `chat/tool_registry.lua:add_tool_system_prompt` | — |
| `viewport` | `shared/editor_context/viewport.lua` | — |

Inline-only tags (`system_tag`, `visual`) live entirely inside `interactions/inline/` and are not part of the shared module.

String values are stable — they appear in stored chats and are read by external adapters. Adding a new tag is safe; renaming a value is a breaking change.
