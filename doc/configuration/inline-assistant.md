# Configuring the Inline Assistant

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" alt="Inline Assistant">
</p>

CodeCompanion provides an _inline_ strategy for quick, direct interaction with your code. Unlike the chat buffer, the inline assistant integrates responses directly into the current buffer—allowing the LLM to add or replace code as needed.

## Keymaps

The inline assistant supports keymaps for accepting or rejecting changes:

```lua
require("codecompanion").setup({
  strategies = {
    inline = {
      keymaps = {
        accept_change = {
          modes = { n = "ga" },
          description = "Accept the suggested change",
        },
        reject_change = {
          modes = { n = "gr" },
          description = "Reject the suggested change",
        },
      },
    },
  },
}),
```

In this example, `<leader>a` (or `ga` on some keyboards) accepts inline changes, while `gr` rejects them.

## Variables

The plugin comes with a number of [variables](/usage/inline-assistant.html#variables) that can be used alongside your prompt using the `#{}` syntax (e.g., `#{my_new_var}`). You can also add your own:

```lua
require("codecompanion").setup({
  strategies = {
    inline = {
      variables = {
        ["my_new_var"] = {
          ---@return string
          callback = "/Users/Oli/Code/my_var.lua",
          description = "My shiny new variable",
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
}),
```

## Diff

Please see the [Diff section](chat-buffer#diff) on the Chat Buffer page for configuration options.
