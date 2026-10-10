---
description: "Install and configure extensions that add features to CodeCompanion, whether from a plugin or your own config."
---

# Configuring Extensions

_Extensions_ add features to CodeCompanion, in the same way as Telescope's extensions. They're distributed as Neovim plugins or defined locally in your config.

## Installing Extensions

To install the mcphub extension with lazy.nvim:

1. Add the extension as a dependency:

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "ravitemer/mcphub.nvim",
  },
}
```

2. Add it to the `extensions` table, with any options:

```lua
require("codecompanion").setup({
  extensions = {
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        make_vars = true,
        make_slash_commands = true,
        show_result_in_chat = true,
      },
    },
  },
})
```

`callback` can be a module path, a table or a function that returns one. Without it, CodeCompanion loads `codecompanion._extensions.<name>` from your runtime path. `opts` is passed to the extension's `setup` function.

## Disabling

Extensions are enabled once they're in the `extensions` table. To turn one off without removing its config:

```lua
require("codecompanion").setup({
  extensions = {
    mcphub = {
      enabled = false,
    },
  },
})
```

To create your own, see [Extending with Extensions](/extending/extensions).
