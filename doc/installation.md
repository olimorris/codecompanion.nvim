# Installation

> [!IMPORTANT]
> The plugin requires the markdown Tree-sitter parser to be installed with `:TSInstall markdown`

## Requirements

- The `curl` library
- Neovim 0.10.0 or greater
- _(Optional)_ An API key for your chosen LLM

## Installation

The plugin can be installed with the plugin manager of your choice:

### [Lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = true
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

## Completion

Out of the box, the plugin supports completion with both [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and [blink.cmp](https://github.com/Saghen/blink.cmp). For the latter, ensure that you've added `codecompanion` as a source:

```lua
sources = {
  default = { "lsp", "path", "snippets", "buffer", "codecompanion" }
},
```

The plugin also supports native completion.

## Troubleshooting

Run `:checkhealth codecompanion` to check that plugin is installed correctly.
