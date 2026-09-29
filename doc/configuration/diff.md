---
description: "Configure CodeCompanion's built-in diff engine in Neovim, covering the chat buffer threshold, floating window size and word level highlights."
---

# Configuring the Diff

<img src="https://github.com/user-attachments/assets/8d80ed10-12f2-4c0b-915f-63b70797a6ca" alt="Diff"/>

CodeCompanion has a built-in diff engine that's leveraged throughout the plugin. If you utilize the `insert_edit_into_file` tool or use an ACP adapter, then the plugin will update files and buffers, displaying the changes in a floating window.

For small changes, the diff is shown directly in the chat buffer. This can be controlled by `threshold_for_chat`, which corresponds to the size of the diff in terms of changed lines. For larger changes, the diff will automatically open in a floating window when the chat buffer is active. Or, you will be prompted to view the diff manually (`gv` by default).

There are a number of configuration options available to you:

::: code-group

```lua [Display]
require("codecompanion").setup({
  display = {
    diff = {
      enabled = true,

      -- At or below this diff size, always display the diff in the chat buffer
      threshold_for_chat = 6,

      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
  },
})
```

```lua [Window Opts] {5-17}
require("codecompanion").setup({
  display = {
    diff = {
      enabled = true,
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
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
  },
})
```

:::
