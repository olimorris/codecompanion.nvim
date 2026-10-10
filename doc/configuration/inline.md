---
description: "Choose the adapter, keymaps, editor context and layout for the inline interaction, which writes an LLM's response straight into a Neovim buffer."
---

# Configuring the Inline Interaction

> [!IMPORTANT]
> Only **http** adapters whose model supports tool calling can be used for the inline interaction

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" alt="Inline Interaction">
</p>

CodeCompanion provides an _inline_ interaction for quick, direct editing of your code. Unlike the chat buffer, the LLM edits the current buffer directly, using the same `edit_file` tool as the chat buffer.

## Changing Adapter

The inline interaction uses the `copilot` adapter by default. To change it:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5-20251001",
      },
    },
  },
})
```

See [Configuring HTTP Adapters](/configuration/adapters-http) for more.

## Keymaps

The keymaps for reviewing an inline diff are shared with the chat buffer's diff. `accept_hunk`, `reject_hunk` and `undo_hunk` only apply to the inline interaction:

```lua
require("codecompanion").setup({
  interactions = {
    shared = {
      keymaps = {
        accept_change = {
          modes = { n = "g2" },
        },
        reject_change = {
          modes = { n = "g3" },
        },
        accept_hunk = {
          modes = { n = "ga" },
        },
        reject_hunk = {
          modes = { n = "gr" },
        },
        undo_hunk = {
          modes = { n = "u" },
        },
        next_hunk = {
          modes = { n = "}" },
        },
        previous_hunk = {
          modes = { n = "{" },
        },
        show_keymaps = {
          modes = { n = "?" },
        },
      },
    },
  },
})
```

You can also cancel an inline request with:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      keymaps = {
        stop = {
          modes = { n = "q" },
          index = 4,
          callback = "keymaps.stop",
          description = "Stop request",
        },
      },
    },
  },
})
```

The keymaps for accepting and rejecting a change, `g1`, `g2` and `g3`, are shared with the chat buffer and live under `interactions.shared.keymaps`. See [Configuring the Diff](/configuration/diff).

## Editor Context

_Editor context_ shares part of your Neovim session with the LLM, using the `#{}` syntax in a prompt. Alongside the [built-in items](/usage/inline#editor-context), you can add your own:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      editor_context = {
        ["my_context_item"] = {
          path = "/Users/Oli/Code/my_context_item.lua",
          description = "My context item",
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
})
```

## Context Limit

The inline interaction shares the whole buffer with the LLM, unless it's over a token limit. Then it shares the lines around your cursor, or your selection, up to the limit. By default, the limit is 16,000 tokens. To change it:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      opts = {
        max_context_tokens = 8000,
      },
    },
  },
})
```

If the model's input limit minus 3,000 is smaller, that's used instead, leaving room for the prompt and the reply.

## Rules and Skills

Edits should follow your project's conventions, so the inline interaction sends your [rules](/configuration/rules) with every prompt. By default that's the `default` group, which includes `AGENTS.md` and `CLAUDE.md`. To choose the groups:

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      inline = {
        autoload = { "default", "my_project_rules" }, -- Can be a string, a list or a function returning either
      },
    },
  },
})
```

Set `autoload = {}` to send no rules. Rules sent this way don't count towards the [context limit](#context-limit).

[Skills](/configuration/skills) aren't sent by default. Inline makes a single request with no time to read a skill when it needs one, so the full instructions of each skill you name go with every prompt:

```lua
require("codecompanion").setup({
  skills = {
    opts = {
      inline = {
        autoload = { "lua-developer" },
      },
    },
  },
})
```

> [!NOTE]
> Rules and skills are only sent to HTTP adapters. An ACP agent loads its own

## Diff

Changes to an existing buffer are shown as a diff before they're kept. To write them straight to the buffer instead, turn off `display.diff.enabled`. See [Configuring the Diff](/configuration/diff).
