---
description: "Run chat titles, compaction and the tool judge on a cheaper model than your main chat."
---

# Using a Cheaper Model for Background Tasks

Some requests CodeCompanion makes don't need your best model. Naming a chat, summarising a long conversation or judging whether a command is safe to run are short, well-defined tasks that a small, fast model handles well, at a fraction of the cost.

## The Background Interaction

The _background_ interaction sends requests to an LLM without any input from you. It never streams, and it fails silently, so a broken background request won't interrupt your chat. Three tasks can run on a model of your choosing:

- **[Chat titles](#chat-titles)** - Names a chat buffer from its first message. Off by default
- **[Tool judge](#tool-judge)** - Decides whether a tool call in Auto mode is safe to run without asking. Off by default
- **[Compaction](#compaction)** - Summarises the chat when it nears the context window. On by default

Chat titles and the tool judge use the background adapter. **Compaction doesn't.** It uses the chat's own adapter unless you give it one.

## Setting the Background Adapter

The background adapter defaults to `copilot`. To point it at a cheaper model:

::: code-group

```lua [Copilot]
require("codecompanion").setup({
  interactions = {
    background = {
      adapter = {
        name = "copilot",
        model = "claude-haiku-4.5",
      },
    },
  },
})
```

```lua [Anthropic]
require("codecompanion").setup({
  interactions = {
    background = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5",
      },
    },
  },
})
```

```lua [OpenAI]
require("codecompanion").setup({
  interactions = {
    background = {
      adapter = {
        name = "openai",
        model = "gpt-5.4-nano",
      },
    },
  },
})
```

```lua [Gemini]
require("codecompanion").setup({
  interactions = {
    background = {
      adapter = {
        name = "gemini",
        model = "gemini-3.1-flash-lite-preview",
      },
    },
  },
})
```

```lua [Local Model]
-- Requires Ollama to be running
require("codecompanion").setup({
  interactions = {
    background = {
      adapter = {
        name = "ollama",
        model = "qwen3:4b",
      },
    },
  },
})
```

:::

> [!IMPORTANT]
> The background adapter doesn't follow your chat adapter. If you've switched your chat to another provider and aren't signed in to Copilot, set this too, or your background tasks will fail without telling you

## Chat Titles

Title generation is off by default. To turn it on:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5",
      },
      chat = {
        opts = {
          enabled = true,
        },
      },
    },
  },
})
```

The title is used as the buffer name and as the chat's description in the [action palette](/usage/action-palette). A chat that already has a title, such as one restored from a [session](/configuration/sessions), isn't renamed.

`chat.opts.enabled` switches on every action in `interactions.background.chat.callbacks`. To give one action its own model, swap its path for a table:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      chat = {
        callbacks = {
          ["on_ready"] = {
            actions = {
              {
                path = "interactions.background.builtin.chat_make_title",
                adapter = { name = "ollama", model = "qwen3:4b" },
              },
            },
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

See [Background Callbacks](/configuration/callbacks#background-callbacks) to attach your own actions.

## Tool Judge

The judge vets a tool call in [Auto mode](/usage/chat-buffer/agents-tools#approval-modes) and only asks you when it thinks the call is unsafe. It uses the background adapter unless you give it one:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      gates = {
        judge = {
          adapter = {
            name = "openai",
            model = "gpt-5-mini",
          },
        },
      },
    },
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            judge = true,
          },
        },
      },
    },
  },
})
```

The judge is switched on per tool, and doesn't depend on `background.chat.opts.enabled`. If it can't reach a verdict, it asks you. See [LLM Judge](/configuration/tools#llm-judge) for the full set of options.

> [!TIP]
> The judge is a safety check, so this is the one task where a slightly stronger small model can be worth the extra cost

## Compaction

Compaction summarises the chat once it reaches 85% of the context window. To run the summary on a cheaper model, with a fallback to the chat's adapter if that model fails:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          compaction = {
            adapter = {
              name = "gemini",
              model = "gemini-3.5-flash",
            },
            fallback_to_chat_adapter = true,
          },
        },
      },
    },
  },
})
```

Pick a model with a context window at least as large as your chat model's, as it has to read the conversation it's summarising. See [Compaction](/configuration/context-management#compaction) for the triggers.

Compaction never runs for agents, as they manage their own context. It also doesn't run for models that compact on the provider's side, such as some `anthropic` and `openai` models, unless you [disable server-side compaction](/configuration/adapters-http#disabling-compaction).

## Other Interactions

The inline and cmd interactions each have their own adapter, so you can give them a cheaper model too:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5",
      },
    },
    cmd = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5",
      },
    },
  },
})
```

A [prompt library](/configuration/prompt-library) item can also set `opts.adapter`, so a prompt that only writes a commit message doesn't have to use your chat model.

## Limitations

- Only HTTP adapters can be background adapters. Setting an agent, such as `claude_code`, logs a warning and the task doesn't run
- Background failures are only written to the [log](/troubleshooting). If titles stop appearing, check the log first
- Chat titles and the judge ask for a structured response. A model that can't return one still produces titles, but the judge will ask you every time
- The `/compact` slash command always uses the chat's adapter, ignoring `compaction.adapter`
