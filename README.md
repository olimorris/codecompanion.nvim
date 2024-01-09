<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5bc2145f-4a26-4cee-9e3c-57f2393b070f" alt="CodeCompanion.nvim" />
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
  <p><strong>Code author</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5bcd3bb4-b763-4812-a686-c2ef5215dc99" alt="code author" /></p>
  <p><strong>Code advisor</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/bc6181e0-85a8-4009-9cfc-f85898780bd5" alt="code advisor" /><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/cbfafcc0-87f9-43e5-8e27-f8eaaf88637d" alt="code advisor" /></p>
</div>

## :zap: Requirements

- An API key from OpenAI (get one [here](https://platform.openai.com/api-keys))
- The `curl` library installed
- Neovim 0.9.0 or greater

## :package: Installation

- Set your OpenAI API Key as an environment variable in your shell (default `OPENAI_API_KEY`)
- Install the plugin with your package manager of choice:

```lua
-- Lazy.nvim
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    {
      "stevearc/dressing.nvim", -- Optional: Improves the default Neovim UI
      opts = {},
    },
  },
  cmd = { "CodeCompanionChat", "CodeCompanionActions" },
  config = true
}

-- Packer.nvim
use({
  "olimorris/codecompanion.nvim",
  config = function()
    require("codecompanion").setup()
  end,
  requires = {
    "stevearc/dressing.nvim"
  }
})
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
    auto_save = true, -- Once a conversation is created/loaded, automatically save it
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/conversations",
  },
  display = { -- How to display `advisor` outputs
    type = "popup", -- "popup"|"split"
    height = 0.7,
    width = 0.8,
  },
  log_level = "TRACE", -- One of: TRACE, DEBUG, ERROR
  send_code = true, -- Send your code to OpenAI
  use_default_actions = true, -- The actions that appear in the action palette
}
```

> **Note**: The `send_code` option can prevent any visual selections from being sent to OpenAI for processing as part of any `advisor` or `author` actions

## :rocket: Usage

The plugin has a number of commands:

- `CodeCompanionChat` - To open up a new chat buffer
- `CodeCompanionActions` - To open up the action selector window
- `CodeCompanionSaveConversationAs` - Saves the chat buffer as a conversation

They can be assigned to keymaps with:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionChat<cr>", { noremap = true, silent = true })
```

> **Note**: For some actions, visual mode allows your selection to be sent to the chat buffer or OpenAI themselves

### The Action Palette

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/1f5a20df-b838-4746-96bc-6af5312e1308" alt="action selector" /></p>

The Action Palette, opened via `:CodeCompanionActions`, contains all of the actions and their associated strategies for the plugin. It's the fastest way to start leveraging CodeCompanion. Depending on whether you're in _normal_ or _visual_ mode will affect the options that are available in the palette.

You may add your own actions into the palette by altering your configuration:

```lua
require("codecompanion").setup({
  actions = {
    {
      name = "My new action",
      strategy = "chat"
      description = "Some cool action you can do",
    }
  }
})
```

> **Note**: We describe how to do this in detail within the `RECIPES.md` file

Or, if you wish to turn off the default actions, set `use_default_actions = false` in your config.

### The Chat Buffer

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/84d5e03a-0b48-4ffb-9ca5-e299d41171bd" alt="chat buffer" /></p>

The Chat Buffer is where you can converse with OpenAI, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (`:h writing`), autocmds trigger the sending of its content to the OpenAI API in the form of prompts. These prompts are segmented by H1 headers into `user` and `assistant` (see OpenAI's [Chat Completions API](https://platform.openai.com/docs/guides/text-generation/chat-completions-api)). When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with ChatGPT, from within Neovim.

> **Note**: You can cancel a request at any point by pressing `q`.

At the very top of the Chat Buffer are the parameters which can be changed to affect the API's response back to you. You can find more detail about them by moving the cursor over them or referring to the [Chat Completions reference guide](https://platform.openai.com/docs/api-reference/chat). The parameters can be tweaked and modified throughout the conversation.

Chat Buffers are not automatically saved into sessions owing to them being an `acwrite` buftype (`:h buftype`). However the plugin allows for this via the notion of Conversations. Simply run `:CodeCompanionSaveConversationAs` in the buffer you wish to save. Conversations can then be restored via the Action Palette and the _Load conversations_ actions.

### In-Built Actions

To be updated

## :clap: Credit

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer.
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action
- [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) for the calculation of tokens
