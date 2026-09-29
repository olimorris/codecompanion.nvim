---
description: "Configure how CodeCompanion keeps a Neovim chat buffer inside the LLM's context window, with triggers for context editing and compaction."
---

# Configuring Context Management

CodeCompanion can manage context in the chat buffer to try and prevent breaching the LLM's context window and to avoid [context rot](https://towardsdatascience.com/governed-context-managing-context-rot-in-claude-code/) setting in. It can be enabled with:

::: code-group

```lua [Boolean]
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          enabled = true,
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
            if adapter.type ~= "http" then
              return false
            end
            return true
          end,
        },
      },
    },
  },
})
```

:::

CodeCompanion runs two operations to keep the chat buffer under the context window: **editing** (which removes old tool results from the message history) and **compaction** (which summarises the message history). Both are triggered separately and can be expressed as a decimal (for a percentage of the context window) or an integer (for an absolute token count). You can read more about how the two operations work in the [architecture](/architecture#in-the-chat-buffer) section.

> [!NOTE]
> Some adapters (Anthropic, OpenAI Responses) manage context themselves, server-side, as part of the request

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

## Editing

Editing replaces the content of older tool results with a placeholder, leaving the conversation shape intact. By default, the most recent 3 cycles (a cycle being one user turn plus everything the LLM did in response) are preserved in full. You can also exclude specific tools from being edited — useful for tools whose output is referenced again later in the conversation.

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          editing = {
            trigger = 0.65, -- Context editing is triggered when X% of the context window is reached
            exclude_tools = { "memory" }, -- Output from these tools is never edited
            keep_cycles = 3, -- Keep the last N cycles of tool results
          },
        },
      },
    },
  },
})
```

## Compaction

Compaction summarises the chat via a single LLM call and replaces the message history with that summary. You can point compaction at a different adapter — handy if you want a cheaper or faster model handling the summary — and choose whether a failure should silently fall back to the chat adapter.

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          compaction = {
            trigger = 0.85, -- Compaction is triggered when X% of the context window is reached
            min_token_savings = 10000, -- Only compact when at least this amount of tokens will be saved

            ---The adapter to use for compaction. Defaults to the current chat adapter
            ---@type nil|string|{ name: string, model:string }
            adapter = nil,

            fallback_to_chat_adapter = false, -- on failure, retry with the chat adapter?
          },
        },
      },
    },
  },
})
```
