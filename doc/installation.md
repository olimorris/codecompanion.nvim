# Installation

> [!IMPORTANT]
> The plugin requires the markdown and markdown_inline Tree-sitter parsers to be installed with `:TSInstall markdown markdown_inline`

## Requirements

- The `curl` library
- Neovim 0.10.0 or greater
- _(Optional)_ An API key for your chosen LLM
- _(Optional)_ The `base64` library for image/vision support

## Installation

The plugin can be installed with the plugin manager of your choice:

### [Lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "olimorris/codecompanion.nvim",
  opts = {},
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
},
```

### [Packer](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "olimorris/codecompanion.nvim",
  config = function()
    require("codecompanion").setup()
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  }
}),
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
call plug#begin()

Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'olimorris/codecompanion.nvim'

call plug#end()

lua << EOF
  require("codecompanion").setup()
EOF
```

**Pinned plugins**

As per [#377](https://github.com/olimorris/codecompanion.nvim/issues/377), if you pin your plugins to the latest releases, ensure you set plenary.nvim to follow the master branch:

```lua
{ "nvim-lua/plenary.nvim", branch = "master" },
```

## Installing Extensions

CodeCompanion supports extensions that add additional functionality to the plugin. Below is an example which installs and configures the [MCP Hub](extensions/mcphub.html) extension:

1. Install with:

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "ravitemer/mcphub.nvim"
  }
}
```

2. Configure with additional options:

```lua
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

Visit the [extensions documentation](extending/extensions) to learn more about available extensions and how to create your own.

## Additional Plugins

CodeCompanion integrates with a number of other plugins to make your AI coding experience more enjoyable. Below are some common lazy.nvim configurations for popular plugins:

### [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)

To render the markdown in the chat buffer:

```lua
{
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" }
},
```

### [markview.nvim](https://github.com/OXY2DEV/markview.nvim)

To render the markdown in the chat buffer:

```lua
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

### [img-clip.nvim](https://github.com/hakonharnes/img-clip.nvim)

To enable you to copy images from your system clipboard into a chat buffer via `:PasteImage`:

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

When in the [Chat Buffer](usage/chat-buffer/index), completion can be used to more easily add [variables](usage/chat-buffer/variables), [slash commands](usage/chat-buffer/slash-commands) and [tools](usage/chat-buffer/agents). Out of the box, the plugin supports completion with both [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and [blink.cmp](https://github.com/Saghen/blink.cmp). For the latter, on version <= 0.10.0, ensure that you've added `codecompanion` as a source:

```lua
sources = {
  per_filetype = {
    codecompanion = { "codecompanion" },
  }
},
```

The plugin also supports [native completion](usage/chat-buffer/index#completion).

## Help

If you're having trouble installing the plugin, as a first step, run `:checkhealth codecompanion` to check that plugin is installed correctly. After that, consider using the [minimal.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/minimal.lua)  file to troubleshoot, running it with `nvim --clean -u minimal.lua`.
