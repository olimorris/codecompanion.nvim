---
description: "Choose when CodeCompanion shows a diff, where it appears and how it's highlighted."
---

# Configuring the Diff

<img src="https://github.com/user-attachments/assets/8d80ed10-12f2-4c0b-915f-63b70797a6ca" alt="Diff"/>

CodeCompanion shows a _diff_ before the `edit_file` tool, an ACP agent or the [inline interaction](/usage/inline) changes a file, so you can accept or reject it.

How a diff from the chat buffer appears depends on its size:

- **Small** - at or below `threshold_for_chat` changed lines, it's shown in the chat buffer
- **Larger** - it opens in a floating window if the chat buffer is active
- **Otherwise** - you're asked to approve the change, and can press `gv` to view the diff

This can be configured with:

::: code-group

```lua [Display]
require("codecompanion").setup({
  display = {
    diff = {
      enabled = true,
      threshold_for_chat = 6, -- Set to 0 to always use the floating window
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
  },
})
```

```lua [Window]
require("codecompanion").setup({
  display = {
    diff = {
      window = {
        ---@return number|fun(): number
        width = function()
          return math.min(120, vim.o.columns - 10)
        end,
        ---@return number|fun(): number
        height = function()
          return vim.o.lines - 4
        end,
        opts = {
          number = true,
        },
      },
    },
  },
})
```

:::

With `enabled = false`, the `edit_file` tool and the inline interaction apply changes without a diff. ACP agents always show one. The diff window inherits any option you don't set from `display.chat.floating_window`, described in [Configuring the Chat Buffer UI](/configuration/ui#layout). A `width` or `height` below 1 is a share of the editor's size.

The keymaps for accepting and rejecting changes are under `interactions.shared.keymaps`. See [Keymaps](/configuration/chat-buffer#keymaps).
