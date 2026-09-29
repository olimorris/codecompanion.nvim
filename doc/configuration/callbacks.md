---
description: "Hook into the CodeCompanion chat buffer lifecycle in Neovim with callbacks: prevent submission, truncate tool output and inspect messages at checkpoints."
---

# Configuring Callbacks

Callbacks allow you to hook into the chat buffer's lifecycle and react to specific events. They are registered per-chat and receive the chat instance as the first argument.

## Available Events

| Event | Description | Extra Args |
|---|---|---|
| `on_created` | Chat buffer has been created | - |
| `on_before_submit` | Before the message is sent to the LLM. Return `false` to prevent submission | `{ adapter }` |
| `on_submitted` | After the message has been sent to the LLM | `{ payload }` |
| `on_checkpoint` | Fires at safe points during the chat lifecycle. Messages are mutable | `{ adapter, estimated_tokens, messages, reported_tokens }` |
| `on_tool_output` | Before tool output is added to the chat. Mutate `args.for_llm`/`args.for_user` to modify | `{ tool, for_llm, for_user }` |
| `on_ready` | Chat is ready for the next turn (after LLM response) | - |
| `on_completed` | LLM response has been fully processed | `{ status }` |
| `on_cancelled` | Request has been stopped/cancelled | - |
| `on_closed` | Chat buffer has been closed | - |

## Registering Callbacks

Callbacks can be registered in two ways:

::: code-group

```lua [All Chats]
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_before_submit", function(c, info)
      -- Access the adapter via info.adapter
      -- Access messages via c.messages
    end)
  end,
})
```

```lua [Prompt Library]
require("codecompanion").setup({
  prompt_library = {
    ["My Prompt"] = {
      opts = {
        callbacks = {
          on_before_submit = function(chat, info)
            -- Only applies to chats opened from this prompt
          end,
        },
      },
    },
  },
})
```

:::

## Background Callbacks

Callbacks can also be registered in the config via `interactions.background.chat.callbacks`. These run asynchronously using a separate background LLM instance and are suited for fire-and-forget tasks like generating chat titles. Unlike the callbacks above, they cannot return values to influence the chat's behavior:

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

The `actions` table contains module paths that are resolved and executed asynchronously. See the [generating titles](/usage/chat-buffer/#generating-titles) section for a working example.

> [!TIP]
> You can change the adapters used for background callbacks, see the [background interaction adapters](/configuration/adapters-http#background-interaction-adapters) section

## Preventing Submission

The `on_before_submit` callback can return `false` to prevent a message from being sent to the LLM. When cancelled, `chat:restore()` is called automatically, which resets the buffer to an editable state and fires a `CodeCompanionChatRestored` event. The user's message remains in the buffer so it can be edited and resubmitted.

This is useful for implementing safeguards such as token/context limit checks:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_before_submit", function(c, data)
      local token_count = my_tokenizer.count(c.messages)
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

The `info` table passed to `on_before_submit` contains:

- `adapter` - A safe copy of the current adapter (with name, model, features, schema, etc.)

## Truncating Tool Output

The `on_tool_output` callback fires before a tool's output is added to the chat. The `args` table contains `tool` (the tool name), `for_llm` (the content sent to the LLM) and `for_user` (what's shown in the buffer). Mutate `args.for_llm` and/or `args.for_user` to modify the output:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_tool_output", function(c, data)
      local tokens = require("codecompanion.utils.tokens")
      local max_tokens = 10000

      if data.for_llm and tokens.calculate(data.for_llm) > max_tokens then
        -- Trim to roughly max_tokens worth of characters
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

The `on_checkpoint` callback fires at various safe points during the chat lifecycle, giving you the ability to inspect and mutate the message stack before the chat continues. It fires:

- **Before submit** — Before a request is sent to an LLM
- **After tool output** — Once tools in the current batch have finished, ensuring no orphaned tool calls
- **After a response with no tools** — When the LLM responds, minus any tool calls

The `data` table contains:

- `adapter` — a safe copy of the current adapter (includes `meta.context_window` for HTTP adapters)
- `estimated_tokens` — client-side token estimate across all messages
- `messages` — a **mutable reference** to the chat's message stack. Changes made here persist back to the chat
- `reported_tokens` — server-reported token count (if available from the adapter)

This is useful for monitoring context window usage and compacting the message stack:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_checkpoint", function(c, data)
      local context_window = data.adapter.meta and data.adapter.meta.context_window
      if not context_window then
        return
      end

      local usage = data.estimated_tokens / context_window
      if usage > 0.8 then
        vim.notify(
          string.format("Context window %.0f%% full", usage * 100),
          vim.log.levels.WARN
        )
        -- Compact data.messages in-place here
      end
    end)
  end,
})
```
