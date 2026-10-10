---
description: "Choose the adapter, keymaps, editor context and layout for the inline interaction, which writes an LLM's response straight into a Neovim buffer."
---

# Configuring the Inline Interaction

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" alt="Inline Interaction">
</p>

The _inline interaction_ writes an LLM's response straight into the current buffer, adding or replacing code rather than opening a chat. See [Using the Inline Interaction](/usage/inline) for the workflow.

> [!IMPORTANT]
> The inline interaction only works with HTTP adapters

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

Press `q` to stop a running request. The default is:

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

`path` can be a Lua module or a file path, and must return a table with a `new(args)` constructor and an `output()` method that returns the text to send. For something smaller, set `callback` to a function that returns the text instead.

A `path` item with `contains_code = true` is skipped when [`send_code`](/configuration/others#sending-code) is `false`.

## Layout

When a response goes into a new buffer, it opens in a vertical split by default. To change that:

```lua
require("codecompanion").setup({
  display = {
    inline = {
      layout = "vertical", -- Can be "vertical", "horizontal", "tab" or "buffer"
    },
  },
})
```

`buffer` opens it in the current window.

## Diff

Changes to an existing buffer are shown as a diff before they're kept. To write them straight to the buffer instead, turn off `display.diff.enabled`. See [Configuring the Diff](/configuration/diff).
