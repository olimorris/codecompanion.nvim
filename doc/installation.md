---
description: How to install CodeCompanion and it's dependencies
---

# Installation

> [!IMPORTANT]
> To avoid breaking changes, it is recommended to pin the plugin to a specific release when installing.

## Requirements

- The `curl` library
- Neovim 0.11.0 or greater
- _(Optional)_ An API key for your chosen LLM
- _(Optional)_ [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) and a `yaml` parser for markdown prompt library items
- _(Optional)_ The [file](https://man7.org/linux/man-pages/man1/file.1.html) command for detecting image mimetype
- _(Optional)_ The [ripgrep](https://github.com/BurntSushi/ripgrep) library for the `grep_search` tool

You can run `:checkhealth codecompanion` to verify that all requirements are met.

## Installation

The plugin can be installed with the plugin manager of your choice. It is recommended to pin the plugin to a specific release to avoid breaking changes.

[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is required if you plan to use markdown prompts in the [prompt library](/configuration/prompt-library), ensuring you have the `yaml` parser installed.

::: code-group

```lua [vim.pack]
vim.pack.add("https://www.github.com/nvim-lua/plenary.nvim")
vim.pack.add("https://github.com/nvim-treesitter/nvim-treesitter")
vim.pack.add({
  src = "https://www.github.com/olimorris/codecompanion.nvim",
  version = vim.version.range("^18.0.0")
})

-- Somewhere in your config
require("codecompanion").setup()
```

```lua [Lazy.nvim]
{
  "olimorris/codecompanion.nvim",
  version = "^18.0.0",
  opts = {},
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
},
```

```lua [Packer.nvim]
use({
  "olimorris/codecompanion.nvim",
  tag = "^18.0.0",
  config = function()
    require("codecompanion").setup()
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
}),
```

:::

**Plenary.nvim note:**

As per [#377](https://github.com/olimorris/codecompanion.nvim/issues/377), if you pin your plugins to the latest releases, ensure you set plenary.nvim to follow the master branch

## Extensions

CodeCompanion supports extensions that add additional functionality to the plugin. Below is an example which installs and configures [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim):

::: code-group

```lua [1. Install]
-- Lazy.nvim
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "ravitemer/mcphub.nvim"
  }
}
```

```lua [2. Configure]
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

:::

Visit the [extensions documentation](extending/extensions) to learn more about available extensions and how to create your own.

## Other Plugins

CodeCompanion integrates with a number of other plugins to make your AI coding experience more enjoyable. Below are some common lazy.nvim configurations for popular plugins:

::: code-group

```lua [render-markdown.nvim]
{
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" }
},
```

```lua [markview.nvim]
{
  "OXY2DEV/markview.nvim",
  lazy = false,
  opts = {
    preview = {
      filetypes = { "markdown", "codecompanion" },
      ignore_buftypes = {},
    },
  },
},
```

```lua [img-clip.nvim]
{
  "HakonHarnes/img-clip.nvim",
  opts = {
    filetypes = {
      codecompanion = {
        prompt_for_file_name = false,
        template = "[Image]($FILE_PATH)",
        use_absolute_path = true,
      },
    },
  },
},
```

:::

Use [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) or [markview.nvim](https://github.com/OXY2DEV/markview.nvim) to render the markdown in the chat buffer.  Use [img-clip.nvim](https://github.com/hakonharnes/img-clip.nvim) to copy images from your system clipboard into a chat buffer via `:PasteImage`:

## Completion

When in the [chat buffer](usage/chat-buffer/index), completion can be used to more easily add [editor context](usage/chat-buffer/editor-context), [slash commands](usage/chat-buffer/slash-commands) and [tools](usage/chat-buffer/tools). Out of the box, the plugin supports completion with both [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and [blink.cmp](https://github.com/Saghen/blink.cmp). For the latter, on version <= 0.10.0, ensure that you've added `codecompanion` as a source:

```lua
sources = {
  per_filetype = {
    codecompanion = { "codecompanion" },
  }
},
```

The plugin also supports [native completion](usage/chat-buffer/index#completion) and [coc.nvim](https://github.com/neoclide/coc.nvim).

## Help

If you're having trouble installing the plugin, as a first step, run `:checkhealth codecompanion` to check that plugin is installed correctly. After that, consider using the [minimal.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/minimal.lua)  file to troubleshoot, running it with `nvim --clean -u minimal.lua`.
