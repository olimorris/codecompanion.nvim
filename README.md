<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/f18e654c-27f6-4712-9913-00ed2f3f4bd9" alt="CodeCompanion.nvim" />
</p>

<h1 align="center">CodeCompanion.nvim</h1>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/issues"><img src="https://img.shields.io/github/issues/olimorris/codecompanion.nvim?color=%23d19a66&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/blob/main/LICENSE"><img src="https://img.shields.io/github/license/olimorris/codecompanion.nvim?style=for-the-badge"></a>
<!-- <a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a> -->
</p>

<p align="center">
Use the <a href="https://platform.openai.com/docs/guides/text-generation/chat-completions-api">OpenAI APIs</a> directly in Neovim. Use it to chat, author and advise you on your code.<br>
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: Chat with the OpenAI APIs via a Neovim buffer
- :sparkles: Built in actions for specific language prompts, LSP error fixes and inline code generation
- :building_construction: Create your own custom actions for Neovim which hook into OpenAI
- :floppy_disk: Save and restore your chats
- :muscle: Async execution for improved performance

## :zap: Requirements

- An API key from OpenAI (get one [here](https://platform.openai.com/api-keys))
- The `curl` library installed
- Neovim 0.9.0 or greater

## :package: Installation

- Set your OpenAI API Key as an environment variable in your shell (default `OPENAI_API_KEY`)
- Install the plugin with your package manager of choice:

**[Lazy.nvim](https://github.com/folke/lazy.nvim)**

```lua
-- Lua
{
  "olimorris/codecompanion.nvim",
  config = true
}
```

**[Packer](https://github.com/wbthomason/packer.nvim)**

```lua
-- Lua
use({
  "olimorris/codecompanion.nvim",
  config = function()
    require("codecompanion").setup()
  end,
})
```

**[Vim Plug](https://github.com/junegunn/vim-plug)**

```vim
" Vim Script
Plug 'olimorris/codecompanion.nvim'

lua << EOF
  require("codecompanion").setup {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
  }
EOF
```

## :wrench: Configuration

The plugin comes with the following defaults

```lua
{
  api_key = "OPENAI_API_KEY", -- Your OpenAI API key
  org_api_key = "OPENAI_ORG_KEY", -- Your organisation OpenAI API key
  conversations = {
    auto_save = true, -- Automatically save conversations as they're updated?
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/conversations",
  },
  log_level = "TRACE", -- One of: TRACE, DEBUG, ERROR
  send_code = true, -- Send your code to OpenAI?
}
```

## :rocket: Usage

The plugin has two primary commands:

- `CodeCompanionChat` - To open up a new chat buffer
- `CodeCompanionActions` - To open up the action selector window

They can be assigned to keymaps with:

```lua

```

## :speech_balloon: The Chat Buffer


## :sparkles: Actions

Actions enable users to interact directly with the OpenAI from within Neovim. This makes it easy to send code from a buffer, along with a prompt, to an OpenAI model before parsing and outputting the response back to a buffer. Most importantly, actions are completely customisable and the plugin allows for new actions to be defined with ease.

The plugin comes with some pre-built actions:

- `Chat` (`chat`) - Open a new chat buffer to converse with the Completions API
- `Chat with selection` (`chat`) - Paste your selected text into a new chat buffer
- `Code Author` (`author`) - Get the Completions API to write/refactor code for you
- `Code Advisor` (`advisor`) - Get advice on the code you've selected
- `LSP Assistant` (`advisor`) - Get help from the Completions API to fix LSP diagnostics

Actions can utilise one of three types of strategies for interacting with the OpenAI APIs:

- `Chat` - An action whereby a user converses with OpenAI directly from a buffer
- `Author` - An action which grants OpenAI the ability to write text into a buffer
- `Advisor` - An action whereby OpenAI can advise on a buffer's content and output into a split/popup and/or a chat

## :clap: Credit

Big props to [Steven Arcangeli](https://github.com/stevearc) for his creation of the chat buffer.
