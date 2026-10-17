---
description: "Keep a chat buffer inside the LLM's context window by editing old tool results and compacting the conversation."
---

# Configuring Context Management

A long chat can outgrow the LLM's context window, and quality drops well before that as [context rot](https://towardsdatascience.com/governed-context-managing-context-rot-in-claude-code/) sets in. CodeCompanion manages the chat buffer's context with two operations:

- **Editing** - replaces old tool results with a placeholder
- **Compaction** - summarises the conversation and replaces the message history with the summary

See [In the Chat Buffer](/architecture#in-the-chat-buffer) for how they work.

Context management is enabled by default for HTTP adapters. To disable it, or decide per adapter:

::: code-group

```lua [Boolean]
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          enabled = false,
        },
      },
    },
  },
})
```

```lua [Function]
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          enabled = function(adapter)
            return adapter.name ~= "ollama"
          end,
        },
      },
    },
  },
})
```

:::

> [!NOTE]
> The `anthropic` and `openai` adapters compact on the server where the model supports it, and CodeCompanion's own context management then stands aside. See [Disabling Compaction](/configuration/adapters-http#disabling-compaction)

## Triggers

Editing and compaction each have a `trigger`. A decimal is a share of the model's context window, and an integer is a token count:

::: code-group

```lua [Decimal]
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          editing = {
            trigger = 0.65, -- 65% of the context window
          },
          compaction = {
            trigger = 0.85, -- 85% of the context window
          },
        },
      },
    },
  },
})
```

```lua [Integer]
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          editing = {
            trigger = 80000, -- tokens
          },
          compaction = {
            trigger = 100000, -- tokens
          },
        },
      },
    },
  },
})
```

:::

A decimal trigger needs the model's context window. If the adapter doesn't report one, that operation is skipped.

## Editing

Editing replaces the content of older tool results with a placeholder, leaving the shape of the conversation intact. The last three _cycles_ are kept in full, where a cycle is one of your messages plus everything the LLM did in response. Tools whose output is referenced again later can be left alone:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          editing = {
            trigger = 0.65,
            exclude_tools = { "memory" },
            keep_cycles = 3,
          },
        },
      },
    },
  },
})
```

## Compaction

Compaction summarises the chat with a single LLM request and replaces the message history with the summary. It's skipped if it would save fewer than `min_token_savings` tokens.

To use a cheaper or faster model for the summary, set an `adapter`. With `fallback_to_chat_adapter`, a failed summary is retried with the chat's own adapter:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          compaction = {
            trigger = 0.85,
            min_token_savings = 10000,
            adapter = { name = "copilot", model = "gpt-4.1" }, -- Can be nil, an adapter name or { name, model }
            fallback_to_chat_adapter = false,
          },
        },
      },
    },
  },
})
```

The `adapter` defaults to the chat's own adapter.

## Limitations

- Context management only runs for HTTP adapters. ACP agents manage their own context
