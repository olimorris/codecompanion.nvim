---
description: How to use the prompts you've defined in your prompt library, in CodeCompanion.
---

# Using the Prompt Library

There are numerous ways that the prompts defined in your prompt library can be used in CodeCompanion. You can invoke them via keymaps, the Action Palette, or slash commands in the chat buffer.

## Keymaps

You can assign prompts from the prompt library to a keymap via the `prompt` function:

```lua
vim.keymap.set("n", "<LocalLeader>d", function()
  require("codecompanion").prompt("docs")
end, { noremap = true, silent = true })
```

Where `docs` is the `alias` of the prompt.

