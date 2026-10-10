---
description: "Hook into the chat buffer's lifecycle to block a submission, trim tool output or edit the message history."
---

# Configuring Callbacks

_Callbacks_ run your own code at set points in a chat buffer's lifecycle. They're registered per chat, and receive the chat as the first argument and a table of event data as the second.

## Events

| Event | Fires | Data |
| --- | --- | --- |
| `on_created` | When the chat buffer is created | - |
| `on_before_submit` | Before a message is sent to the LLM. Return `false` to stop it | `adapter` |
| `on_submitted` | After the message is sent to the LLM | `payload` |
| `on_checkpoint` | At safe points in the chat, with a mutable message history | `adapter`, `estimated_tokens`, `messages`, `reported_tokens` |
| `on_tool_output` | Before a tool's output is added to the chat | `tool`, `for_llm`, `for_user` |
| `on_ready` | When the chat is ready for your next message | - |
| `on_completed` | When the LLM's response is fully processed. `error` is set when `status` is `"error"` | `status`, `error` |
| `on_cancelled` | When a request is stopped | - |
| `on_closed` | When the chat buffer is closed | - |

## Registering Callbacks

Register a callback for every chat with an autocmd, or for chats opened from a [prompt library](/configuration/prompt-library) item:

::: code-group

```lua [All Chats]
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_before_submit", function(chat, data)
      -- data.adapter is a copy of the chat's adapter
    end)
  end,
})
```

```lua [Prompt Library]
require("codecompanion").setup({
  prompt_library = {
    ["Explain Code"] = {
      interaction = "chat",
      description = "Explain how code works",
      opts = {
        callbacks = {
          on_before_submit = function(chat, data)
            -- Only applies to chats opened from this prompt
          end,
        },
      },
      prompts = {
        { role = "user", content = "Explain how this code works" },
      },
    },
  },
})
```

:::

Remove a callback with `chat:remove_callback(event, callback)`, passing the same function you registered.

## Background Callbacks

_Background callbacks_ run asynchronously, using a separate LLM from the [background interaction](/guides/background-model). They suit fire-and-forget tasks like generating chat titles, and unlike the callbacks above, they can't change what the chat does:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      chat = {
        callbacks = {
          ["on_ready"] = {
            actions = {
              "interactions.background.builtin.chat_make_title",
            },
            enabled = true,
          },
        },
        opts = {
          enabled = true,
        },
      },
    },
  },
})
```

Each action is a module path, or a `{ path = "...", adapter = "..." }` table to give that action its own adapter. Background callbacks are off until you set `opts.enabled = true`. See [Generating Titles](/usage/chat-buffer/#generating-titles) for a working example.

> [!TIP]
> To change the adapter for every background callback, see [Background Interaction Adapters](/configuration/adapters-http#background-interaction-adapters)

## Preventing Submission

When `on_before_submit` returns `false`, the message isn't sent. CodeCompanion calls `chat:restore()`, which makes the buffer editable again and fires a `CodeCompanionChatRestored` event. Your message stays in the buffer to edit and send again.

To stop a message that's over a token limit:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_before_submit", function(chat, data)
      local token_count = my_tokenizer.count(chat.messages)
      local context_limit = 128000

      if token_count > context_limit then
        vim.notify(
          string.format("Token count (%d) exceeds context limit (%d)", token_count, context_limit),
          vim.log.levels.WARN
        )
        return false
      end
    end)
  end,
})
```

## Truncating Tool Output

`on_tool_output` fires before a tool's output is added to the chat. `data.tool` is the tool's name, `data.for_llm` is the output sent to the LLM and `data.for_user` is what's shown in the chat buffer. Change either to change the output:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_tool_output", function(chat, data)
      local tokens = require("codecompanion.utils.tokens")
      local max_tokens = 10000

      if data.for_llm and tokens.calculate(data.for_llm) > max_tokens then
        local max_chars = max_tokens * 6
        data.for_llm = data.for_llm:sub(1, max_chars) .. "\n\n[Output truncated]"
        data.for_user = data.for_llm
        vim.notify(
          string.format("Tool output from '%s' truncated (~%d tokens)", data.tool, max_tokens),
          vim.log.levels.WARN
        )
      end
    end)
  end,
})
```

## Checkpoints

`on_checkpoint` fires at points where the message history is safe to change:

- **Before submit** - before a request is sent to the LLM
- **After tool output** - once every tool in the current batch has returned, so no tool call is left without a result
- **After a response with no tools** - when the LLM responds without calling a tool

The `data` table contains:

- **adapter** - a copy of the chat's adapter
- **estimated_tokens** - a client-side estimate of the tokens across all messages
- **messages** - the chat's message history. **Changes made here persist back to the chat**
- **reported_tokens** - the token count reported by the adapter, if it gives one

To warn when the context window is filling up:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_checkpoint", function(chat, data)
      local meta = data.adapter.model and data.adapter.model.meta
      local context_window = meta and meta.context_window
      if not context_window then
        return
      end

      local usage = data.estimated_tokens / context_window
      if usage > 0.8 then
        vim.notify(string.format("Context window %.0f%% full", usage * 100), vim.log.levels.WARN)
      end
    end)
  end,
})
```

> [!NOTE]
> `adapter.model.meta` is only set for adapters with a fixed list of models, so it's `nil` for adapters that fetch theirs

For built-in compaction, see [Configuring Context Management](/configuration/context-management).
