# CodeCompanion Extensions

CodeCompanion supports extensions similar to telescope.nvim, allowing users to create functionality that can be shared with others. Extensions can either be distributed as plugins or defined locally in your configuration.

## Using Extensions

Extensions are configured in your CodeCompanion setup:

```lua
-- Install the extension
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "author/codecompanion_history.nvim" -- history extension
  }
}

-- Configure in your setup
require("codecompanion").setup({
  extensions = {
    codecompanion_history = {
      enabled = true, -- defaults to true
      opts = {
        history_file = vim.fn.stdpath("data") .. "/codecompanion_chats.json",
        max_history = 10, -- maximum number of chats to keep
      }
    }
  }
})
```


## Creating Extensions

Extensions are typically distributed as plugins. Create a new plugin with the following structure:

```
your-extension/
├── lua/
│   └── codecompanion/
│       └── _extensions/
│           └── your_extension/
│               └── init.lua  -- Main extension file
└── README.md
```

The init.lua file should export a module that provides setup and optional exports:

```lua
---@class CodeCompanion.Extension
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.your_extension
local Extension = {}

---Setup the extension
---@param opts table Configuration options 
function Extension.setup(opts)
  -- Initialize extension
  -- Add actions, keymaps etc.
end

-- Optional: Functions exposed via codecompanion.extensions.your_extension
Extension.exports = {
  clear_history = function() end
}

return Extension
```

### Extending Chat Functionality

A common pattern is to add keymaps, slash_commands, tools to the codecompanion.config object inside setup function.

```lua
---This is called on codecompanion setup.
---You can access config via require("codecompanion.config") and chat via require("codecompanion.chat").last_chat() etc
function Extension.setup(opts)
  -- Add action to chat keymaps
  local chat_keymaps = require("codecompanion.config").strategies.chat.keymaps
  
  chat_keymaps.open_saved_chats = {
    modes = {
      n = opts.keymap or "gh", 
    },
    description = "Open Saved Chats",
    callback = function(chat)
        -- Implementation of opening saved chats
        vim.notify("Opening saved chats for " .. chat.id)
    end
  }
end
```

Once configured, extension exports are accessible via:

```lua
local codecompanion = require("codecompanion")
-- Use exported functions
codecompanion.extensions.codecompanion_history.clear_history()
```

## Local Extensions

Extensions can also be defined directly in your configuration for simpler use cases:

```lua
-- Example: Adding a message editor extension
require("codecompanion").setup({
  extensions = {
    editor = {
      enabled = true,
      opts = {},
      callback = {
        setup = function(ext_config)
          -- Add a new action to chat keymaps
          local open_editor = {
            modes = {
              n = "ge",  -- Keymap to open editor
            },
            description = "Open Editor",
            callback = function(chat)
              -- Implementation of editor opening logic
              -- You have access to the chat buffer via the chat parameter
              vim.notify("Editor opened for chat " .. chat.id)
            end,
          }

          -- Add the action to chat keymaps config
          local chat_keymaps = require("codecompanion.config").strategies.chat.keymaps
          chat_keymaps.open_editor = open_editor
        end,

        -- Optional: Expose functions
        exports = {
          is_editor_open = function()
            return false -- Implementation
          end
        }
      }
    }
  }
})
```

The callback can be:
- A function returning the extension table
- The extension table directly 
- A string path to a module that returns the extension

## Dynamic registration

Extensions can also be added dynamically using 

```lua
require("codecompanion").register_extension("codecompanion_history", {
    callback = {
        setup = function()
        end,
        exports = {}
    },
})
```

## Best Practices

1. **Namespacing**:
   - Use unique names for extensions to avoid conflicts
   - Prefix functions and variables appropriately

2. **Configuration**:
   - Provide sensible defaults
   - Allow customization via opts table
   - Document all options

3. **Integration**:
   - Follow CodeCompanion's patterns for actions and tools
   - Use existing utilities like keymaps.set_keymap
   - Handle errors appropriately

4. **Documentation**:
   - Document installation process
   - List all available options
   - Provide usage examples
