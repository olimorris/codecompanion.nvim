---
description: "Run prompts from your prompt library with a keymap, the command line or a slash command in the chat buffer."
---

# Using the Prompt Library

The _prompt library_ holds reusable prompts, both the ones CodeCompanion ships with and any you [write yourself](/configuration/prompt-library). Run them from the [Action Palette](/usage/action-palette), a keymap, the command line or the chat buffer.

## Keymaps

To map a prompt to a key, pass its `alias` to `prompt()`:

```lua
vim.keymap.set("n", "<LocalLeader>d", function()
  require("codecompanion").prompt("docs")
end, { noremap = true, silent = true })
```

## Command Line

Any prompt with an `alias` can be run from the command line:

```
:CodeCompanion /docs
```

## Slash Commands

In the chat buffer, type `/` followed by the alias. Only chat prompts with `is_slash_cmd = true` in their `opts` appear here.

Any tools the prompt declares are added to the chat buffer before its content is inserted.
