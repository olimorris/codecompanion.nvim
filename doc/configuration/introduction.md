# Introduction

This section sets out how various elements of CodeCompanion's config can be changed. The examples are shown wrapped in a `require("codecompanion").setup({})` block to work with all plugin managers.

However, if you're using [Lazy.nvim](https://github.com/folke/lazy.nvim), you can apply config changes in the `opts` table which is much cleaner:

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    strategies = {
      -- Change the default chat adapter
      chat = {
        adapter = "anthropic",
      },
    },
    opts = {
      -- Set debug logging
      log_level = "DEBUG",
    },
  },
},
```
Of course, peruse the rest of this section for more configuration options.
