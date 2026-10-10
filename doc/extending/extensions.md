---
description: "Build a CodeCompanion extension, distributed as a Neovim plugin or defined in your own config."
---

# Extending with Extensions

An _extension_ adds functionality to CodeCompanion, in the same way as extensions for telescope.nvim. Distribute one as a Neovim plugin or define it in your own config.

## Using Extensions

Install the extension alongside CodeCompanion, then configure it under `extensions`:

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "ravitemer/codecompanion-history.nvim",
  },
}
```

```lua
require("codecompanion").setup({
  extensions = {
    history = {
      enabled = true,
      opts = {
        dir_to_save = vim.fn.stdpath("data") .. "/codecompanion_chats.json",
      },
    },
  },
})
```

Extensions are enabled by default. Set `enabled = false` to skip loading one. See [Configuring Extensions](/configuration/extensions) for more.

## Creating Extensions

A plugin extension lives under `lua/codecompanion/_extensions/`, in a directory named after the extension:

```
your-extension/
├── lua/
│   └── codecompanion/
│       └── _extensions/
│           └── your_extension/
│               └── init.lua
└── README.md
```

`init.lua` returns a table with a `setup` function and, optionally, `exports`:

```lua
---@class CodeCompanion.Extension
---@field setup fun(opts: table): any Function called when extension is loaded
---@field exports? table Optional table of functions exposed via codecompanion.extensions.name
local Extension = {}

---@param opts table
function Extension.setup(opts)
  -- Add keymaps, slash commands, tools etc.
end

Extension.exports = {
  clear_history = function() end,
}

return Extension
```

CodeCompanion calls `setup` with the extension's `opts` when you call `require("codecompanion").setup()`.

### Extending the Chat Buffer

Extensions usually add keymaps, slash commands or tools to `require("codecompanion.config")` in `setup`. To add a chat buffer keymap:

```lua
function Extension.setup(opts)
  local chat_keymaps = require("codecompanion.config").interactions.chat.keymaps

  chat_keymaps.open_saved_chats = {
    modes = {
      n = opts.keymap or "gh",
    },
    description = "Open Saved Chats",
    callback = function(chat)
      vim.notify("Opening saved chats for " .. chat.id)
    end,
  }
end
```

To reach a chat from elsewhere, use `require("codecompanion").last_chat()`.

### Exports

Exports are available under the name the extension is configured with:

```lua
require("codecompanion").extensions.history.clear_history()
```

## Local Extensions

To define an extension in your own config, pass it as a `callback`:

```lua
require("codecompanion").setup({
  extensions = {
    editor = {
      enabled = true,
      opts = {},
      callback = {
        setup = function(opts)
          local chat_keymaps = require("codecompanion.config").interactions.chat.keymaps

          chat_keymaps.open_editor = {
            modes = {
              n = "ge",
            },
            description = "Open Editor",
            callback = function(chat)
              vim.notify("Editor opened for chat " .. chat.id)
            end,
          }
        end,
        exports = {
          is_editor_open = function()
            return false
          end,
        },
      },
    },
  },
})
```

The `callback` can be:

- The extension table
- A function that returns the extension table
- A module path that returns the extension, such as `"mcphub.extensions.codecompanion"`

Without a `callback`, CodeCompanion loads `codecompanion._extensions.<name>` from your runtimepath.

## Registering at Runtime

To add an extension after setup:

```lua
require("codecompanion").register_extension("history", {
  setup = function(opts) end,
  exports = {},
})
```

The second argument is the extension table itself, not a `callback`. Its `setup` is called with an empty `opts` table.

## Best Practices

- **Naming** - give your extension a unique name, and prefix its functions and variables to avoid clashes
- **Configuration** - provide sensible defaults, take everything else through `opts` and document every option
- **Integration** - follow CodeCompanion's patterns for keymaps, slash commands and tools, and handle errors with `pcall`
- **Documentation** - cover installation, every option and some usage examples
