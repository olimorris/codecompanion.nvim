---
description: Configure the Inline Assistant in CodeCompanion
---

# Configuring the Inline Assistant

> [!IMPORTANT]
> Only **http** adapters are supported for the inline assistant.

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" alt="Inline Assistant">
</p>

CodeCompanion provides an _inline_ interaction for quick, direct editing of your code. Unlike the chat buffer, the inline assistant integrates responses directly into the current buffer—allowing the LLM to add or replace code as needed.

## Changing Adapter

By default, CodeCompanion sets the _copilot_ adapter for the inline assistant. You can change this to any other HTTP adapter:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5-20251001"
      },
    },
  },
})
```

See the section on [HTTP Adapters](/configuration/adapters-http) for more information.

## Keymaps

The inline assistant supports keymaps for accepting or rejecting changes:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      keymaps = {
        accept_change = {
          modes = { n = "ga" },
          description = "Accept the suggested change",
        },
        reject_change = {
          modes = { n = "gr" },
          opts = { nowait = true },
          description = "Reject the suggested change",
        },
      },
    },
  },
})
```

In this example, `ga` accepts inline changes, while `gr` rejects them.

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

## Editor Context

The plugin comes with a number of [editor context](/usage/inline-assistant.html#editor-context) items that can be used alongside your prompt using the `#{}` syntax (e.g., `#{my_new_context_item}`). You can also add your own:

```lua
require("codecompanion").setup({
  interactions = {
    inline = {
      editor_context = {
        ["my_new_context_item"] = {
          ---@return string
          callback = "/Users/Oli/Code/my_context_item.lua",
          description = "My shiny new context item",
          opts = {
            contains_code = true,
          },
        },
      }
    }
  }
})
```

## Layout

If the inline prompt creates a new buffer, you can also customize if this should be output in a vertical/horizontal split or a new buffer:

```lua
require("codecompanion").setup({
  display = {
    inline = {
      layout = "vertical", -- vertical|horizontal|buffer
    },
  }
})
```

## Diff

Please see the [Diff section](chat-buffer#diff) on the Chat Buffer page for configuration options.
