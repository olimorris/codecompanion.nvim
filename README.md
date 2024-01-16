<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5bc2145f-4a26-4cee-9e3c-57f2393b070f" alt="CodeCompanion.nvim" />
</p>

<h1 align="center">CodeCompanion.nvim</h1>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/issues"><img src="https://img.shields.io/github/issues/olimorris/codecompanion.nvim?color=%23d19a66&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/blob/main/LICENSE"><img src="https://img.shields.io/github/license/olimorris/codecompanion.nvim?style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
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

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p><strong>Chat buffer</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/fd1f11e7-bef4-4bbc-8c7f-0c306e5c72b8" alt="chat buffer" /></p>
  <p><strong>Code author</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/64cf4fa1-d5b9-43cc-8351-4d06c06c8b46" alt="code author" /></p>
  <p><strong>Code advisor</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/bc6181e0-85a8-4009-9cfc-f85898780bd5" alt="code advisor" /><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/cbfafcc0-87f9-43e5-8e27-f8eaaf88637d" alt="code advisor" /></p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- An API key from OpenAI (get one [here](https://platform.openai.com/api-keys))
- The `curl` library installed
- Neovim 0.9.2 or greater

## :package: Installation

- Set your OpenAI API Key as an environment variable in your shell (default name: `OPENAI_API_KEY`)
- Install the plugin with your package manager of choice:

```lua
-- Lazy.nvim
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
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
    "nvim-treesitter/nvim-treesitter",
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
  base_url = "https://api.openai.com", -- The URL to use for the API requests
  ai_settings = {
    -- Default settings for the Completions API
    -- See https://platform.openai.com/docs/api-reference/chat/create
    models = {
      chat = "gpt-4-1106-preview",
      author = "gpt-4-1106-preview",
      advisor = "gpt-4-1106-preview",
    },
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
    type = "popup", -- popup|split
    split = "horizontal" -- horizontal|vertical
    height = 0.7,
    width = 0.8,
  },
  log_level = "ERROR", -- One of: TRACE, DEBUG, ERROR
  send_code = true, -- Send your code to OpenAI
  show_token_count = true, -- Show the token count for the current chat
  use_default_actions = true, -- The actions that appear in the action palette
}
```

Modify these settings via the `opts` table in Lazy.nvim or by calling the `require("codecompanion").setup()` function in Packer.

> **Note**: The `send_code` option can prevent any visual selections from being sent to OpenAI for processing as part of any `advisor` or `author` actions

## :rocket: Usage

The plugin has a number of commands:

- `CodeCompanionChat` - To open up a new chat buffer
- `CodeCompanionActions` - To open up the action selector window
- `CodeCompanionSaveConversationAs` - Saves a chat buffer as a conversation

They can be assigned to keymaps with:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionChat<cr>", { noremap = true, silent = true })
```

> **Note**: For some actions, visual mode allows your selection to be sent directly to the chat buffer or OpenAI themselves (in the case of `author` actions).

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

The Chat Buffer is where you can converse with OpenAI, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written, autocmds trigger the sending of its content to the OpenAI API in the form of prompts. These prompts are segmented by H1 headers into `user` and `assistant` (see OpenAI's [Chat Completions API](https://platform.openai.com/docs/guides/text-generation/chat-completions-api) for more on this). When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with ChatGPT, from within Neovim.

> **Note**: You can cancel a request at any point by pressing `q`.

At the very top of the Chat Buffer are the parameters which can be changed to affect the API's response back to you. You can find more detail about them by moving the cursor over them or referring to the [Chat Completions reference guide](https://platform.openai.com/docs/api-reference/chat). The parameters can be tweaked and modified throughout the conversation.

Chat Buffers are not automatically saved owing to them being an `acwrite` buftype (see `:h buftype`). However, the plugin allows for this via the notion of Conversations. Simply run `:CodeCompanionSaveConversationAs` in the chat buffer you wish to save. Conversations can then be restored via the Action Palette and the _Load conversations_ actions.

> **Note**: When a conversation is saved or loaded it will automatically save any changes.

### In-Built Actions

The plugin comes with a number of [in-built actions](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/actions.lua) which aim to improve your Neovim workflow. Actions make use of strategies which are abstractions built around Neovim and OpenAI functionality. Before we dive in to the actions, it's worth explaining what each of the strategies do:

- `chat` - A strategy for opening up a chat buffer allowing the user to converse directly with OpenAI
- `author` - A strategy for allowing OpenAI responses to be written directly into a Neovim buffer
- `advisor` - A strategy for outputting OpenAI responses into a split or a popup, alongside a Neovim buffer

#### Chat and Chat as

Both of these actions utilise the `chat` strategy. The `Chat` action opens up a fresh chat buffer. The `Chat as` action allows for persona based context to be set in the chat buffer allowing for better and more detailed responses from OpenAI.

> **Note**: Both of these actions allow for visually selected code to be sent to the chat buffer as code blocks.

#### Code author

This action utilises the `author` strategy. This action can be useful for generating code or even refactoring a visual selection based on a prompt by the user. The action is designed to write code for the buffer filetype that it is initated in, or, if run from a terminal prompt, to write commands.

#### Code advisor

As the name suggests, this action provides advice on a visual selection of code and utilises the `advisor` strategy. It uses the `display` configuration option to output the response from OpenAI into a split or a popup. Inevitably, the response back from OpenAI may lead to more questions. Pressing `c` in the advisor buffer will take the conversation to a chat buffer. Pressing `q` will close the buffer.

> **Note**: For some users, the sending of code to OpenAI may not be an option. In those instances, you can set `send_code = false` in your config.

#### LSP assistant

Taken from the fantastic [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) plugin, this action provides advice (utilising the `advisor` strategy) on any LSP diagnostics which occur across visually selected lines and how they can be fixed. Again, the `send_code = false` value can be set in your config to only send diagnostic messages to OpenAI.

## :rainbow: Helpers

### Hooks / User events

The plugin fires events at the start and the conclusion of an API request. A user can hook into these as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanion",
  group = group,
  callback = function(request)
    print(request.data.status) -- outputs "started" or "finished"
  end,
})
```

> **Note**: The author uses these to display an icon in his statusline.

### Heirline.nvim

If you use the fantastic [Heirline.nvim](https://github.com/rebelot/heirline.nvim) plugin, consider the following snippet to display an icon in the statusline whilst CodeCompanion is speaking to the LLM:

```lua
local OpenAI = {
  static = {
    processing = false,
  },
  update = {
    "User",
    pattern = "CodeCompanion",
    callback = function(self, args)
      self.processing = (args.data.status == "started")
      vim.cmd("redrawstatus")
    end,
  },
  {
    condition = function(self)
      return self.processing
    end,
    provider = " ",
    hl = { fg = "yellow" },
  },
}
```

<!-- panvimdoc-ignore-start -->

## :clap: Thanks

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer and his feedback
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action
- [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) for the calculation of tokens

<!-- panvimdoc-ignore-end -->
