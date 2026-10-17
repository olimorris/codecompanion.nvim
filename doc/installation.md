---
description: "Install CodeCompanion.nvim and its dependencies, then add extensions and the plugins it works with."
---

# Installation

> [!IMPORTANT]
> Pin the plugin to a release to avoid breaking changes

## Requirements

- Neovim 0.12 or later
- [curl](https://curl.se)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- _(Optional)_ An API key for your chosen LLM
- _(Optional)_ A Tree-sitter `yaml` parser, for markdown prompts in the [prompt library](/configuration/prompt-library) and [skills](/usage/chat-buffer/skills)
- _(Optional)_ The [file](https://man7.org/linux/man-pages/man1/file.1.html) command, to detect the mimetype of images
- _(Optional)_ [ripgrep](https://github.com/BurntSushi/ripgrep), for the [grep_search](/usage/chat-buffer/agents-tools#grep-search) tool
- _(Optional)_ [MarkItDown](https://github.com/microsoft/markitdown), to fetch webpages with the default adapter
- _(Optional)_ `sqlite3`, to read Copilot tokens from a SQLite database

To check them:

```
:checkhealth codecompanion
```

## Installing

[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is the easiest way to install the `yaml` parser:

::: code-group

```lua [vim.pack]
vim.pack.add({ "https://www.github.com/nvim-lua/plenary.nvim" })
vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter" })
vim.pack.add({ {
  src = "https://www.github.com/olimorris/codecompanion.nvim",
  version = vim.version.range("^19.0.0")
} })

-- Somewhere in your config
require("codecompanion").setup()
```

```lua [Lazy.nvim]
{
  "olimorris/codecompanion.nvim",
  version = "^19.0.0",
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
  tag = "^19.0.0",
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

> [!WARNING]
> If you pin your plugins to their latest releases, keep plenary.nvim on its master branch. See [#377](https://github.com/olimorris/codecompanion.nvim/issues/377)

## Extensions

Extensions add features to CodeCompanion. To install and configure [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim):

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

See [Extending with Extensions](/extending/extensions) for the extensions available and how to write your own.

## Other Plugins

These plugins work well with CodeCompanion. The examples use lazy.nvim.

### Rendering Markdown

[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) and [markview.nvim](https://github.com/OXY2DEV/markview.nvim) render the markdown in the chat buffer:

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

:::

### img-clip.nvim

[img-clip.nvim](https://github.com/hakonharnes/img-clip.nvim) pastes images from your clipboard into the chat buffer with `:PasteImage`:

```lua
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

## Completion

Completion in the [chat buffer](/usage/chat-buffer/#completion) works with [blink.cmp](https://github.com/Saghen/blink.cmp), [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and [coc.nvim](https://github.com/neoclide/coc.nvim), or with Neovim's native completion. On blink.cmp 0.10.0 or earlier, add `codecompanion` as a source:

```lua
sources = {
  per_filetype = {
    codecompanion = { "codecompanion" },
  }
},
```

## Help

If something isn't working, see [Troubleshooting](/troubleshooting).
