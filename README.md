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

## :camera_flash: Screenshots

<div align="center">
  <p><strong>Chat buffer</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/3ae659f4-9758-47d1-8964-531e9f2901cc" alt="chat buffer" /></p>
  <p><strong>Action selector</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/1f5a20df-b838-4746-96bc-6af5312e1308" alt="action selector" /></p>
  <p><strong>Code author</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5bcd3bb4-b763-4812-a686-c2ef5215dc99" alt="code author" /><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/81301839-f5dc-4c79-8e7d-051439ad6c23" alt="code author" /></p>
  <p><strong>Code advisor</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/bc6181e0-85a8-4009-9cfc-f85898780bd5" alt="code advisor" /><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/cbfafcc0-87f9-43e5-8e27-f8eaaf88637d" alt="code advisor" /></p>
</div>

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

The plugin comes with the following defaults:

```lua
{
  api_key = "OPENAI_API_KEY", -- Your OpenAI API key
  org_api_key = "OPENAI_ORG_KEY", -- Your organisation OpenAI API key
  openai_settings = {
    -- Default settings for the Completions API
    -- See https://platform.openai.com/docs/api-reference/chat/create
    model = "gpt-4-1106-preview",
    temperature = 1,
    top_p = 1,
    stop = nil,
    max_tokens = nil,
    presence_penalty = 0,
    frequency_penalty = 0,
    logit_bias = nil,
    user = nil,
  },
  conversations = {
    auto_save = true, -- Automatically save conversations as they're updated?
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/conversations",
  },
  display = { -- How to display `advisor` strategy outputs
    type = "popup", -- Can be "popup" or "split"
    height = 0.7, -- For "popup" only
    width = 0.8, -- For "popup"
  },
  log_level = "TRACE", -- One of: TRACE, DEBUG, ERROR
  send_code = true, -- Send your code to OpenAI?
}
```

> **Note**: The `send_code` option can prevent any visual selections from being sent to OpenAI for processing

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

- Big props to [Steven Arcangeli](https://github.com/stevearc) for his creation of the chat buffer.
- Wtf.nvim
- ChatGPT.nvim
