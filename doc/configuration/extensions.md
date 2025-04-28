# Configuring Extensions

CodeCompanion supports extensions similar to telescope.nvim, allowing users to create functionality that can be shared with others. Extensions can either be distributed as plugins or defined locally in your configuration.

## Installing Extensions

CodeCompanion supports extensions that add additional functionality to the plugin. For example, to install and set up the mcphub extension using lazy.nvim:

1. Install the extension:

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    -- Add mcphub.nvim as a dependency
    "ravitemer/mcphub.nvim" 
  }
}
```

2. Add extension to your config with additional options:

```lua
-- Configure in your setup
require("codecompanion").setup({
  extensions = {
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        make_vars = true,       
        make_slash_commands = true,
        show_result_in_chat = true  
      }
    }
  }
})
```

Visit the [creating extensions guide](extending/extensions) to learn more about available extensions and how to create your own.

