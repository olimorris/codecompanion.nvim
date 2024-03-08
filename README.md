<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/cc50a085-722b-4299-9f26-0373a96c7c55" alt="CodeCompanion.nvim" />
</p>

<h1 align="center">CodeCompanion.nvim</h1>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/issues"><img src="https://img.shields.io/github/issues/olimorris/codecompanion.nvim?color=%23d19a66&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/blob/main/LICENSE"><img src="https://img.shields.io/github/license/olimorris/codecompanion.nvim?style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
</p>

<p align="center">
Use the power of generative AI in Neovim. Use it to chat, author and advise you on your code.<br><br>
Currently supports: Anthropic, Ollama and OpenAI adapters.
</p>

> [!IMPORTANT]
> This plugin is provided as-is and is primarily developed for my own workflows. As such, I offer no guarantees of regular updates or support and I expect the plugin's API to change regularly. Bug fixes and feature enhancements will be implemented at my discretion, and only if they align with my personal use-case. Feel free to fork the project and customize it to your needs, but please understand my involvement in further development will be minimal.

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5e5a5e54-c1d9-4fe2-8ae0-1cfbfdd6cea5" alt="Header" />
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: A Copilot Chat experience from within Neovim
- :electric_plug: Adapter support for many generative AI services
- :rocket: Inline code creation and modification
- :sparkles: Built in actions for specific language prompts LSP error fixes and code advice
- :building_construction: Create your own custom actions for Neovim which hook into generative AI APIs
- :floppy_disk: Save and restore your chats
- :muscle: Async execution for improved performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p><strong>Chat</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/a19c8397-a1e2-44df-98be-8a1b4d307ea7" alt="chat" /></p>
  <p><strong>Inline code</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/909277f9-7a5f-455e-b25a-84e85b47440b" alt="Inline code" /></p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- The `curl` library installed
- Neovim 0.9.2 or greater
- _(Optional)_ An API key to be set in your shell for your chosen generative AI service

## :package: Installation

- Install the plugin with your package manager of choice:

```lua
-- Lazy.nvim
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-lua/plenary.nvim",
    {
      "stevearc/dressing.nvim", -- Optional: Improves the default Neovim UI
      opts = {},
    },
  },
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
    "nvim-lua/plenary.nvim",
    "stevearc/dressing.nvim"
  }
})
```

## :wrench: Configuration

You only need to the call the `setup` function if you wish to change any of the defaults:

<details>
  <summary>Click to see the default configuration</summary>

```lua
require("codecompanion").setup({
  adapters = {
    chat = "openai",
    inline = "openai",
  },
  saved_chats = {
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/saved_chats", -- Path to save chats to
  },
  display = {
    action_palette = {
      width = 95,
      height = 10,
    },
    chat = { -- Options for the chat strategy
      type = "float", -- float|buffer
      show_settings = true, -- Show the model settings in the chat buffer?
      show_token_count = true, -- Show the token count for the current chat in the buffer?
      buf_options = { -- Buffer options for the chat buffer
        buflisted = false,
      },
      float_options = { -- Float window options if the type is "float"
        border = "single",
        buflisted = false,
        max_height = 0,
        max_width = 0,
        padding = 1,
      },
      win_options = { -- Window options for the chat buffer
        cursorcolumn = false,
        cursorline = false,
        foldcolumn = "0",
        linebreak = true,
        list = false,
        signcolumn = "no",
        spell = false,
        wrap = true,
      },
    },
  },
  keymaps = {
    ["<C-s>"] = "keymaps.save", -- Save the chat buffer and trigger the API
    ["<C-c>"] = "keymaps.close", -- Close the chat buffer
    ["q"] = "keymaps.cancel_request", -- Cancel the currently streaming request
    ["gc"] = "keymaps.clear", -- Clear the contents of the chat
    ["ga"] = "keymaps.codeblock", -- Insert a codeblock into the chat
    ["gs"] = "keymaps.save_chat", -- Save the current chat
    ["]"] = "keymaps.next", -- Move to the next header in the chat
    ["["] = "keymaps.previous", -- Move to the previous header in the chat
  },
  log_level = "ERROR", -- TRACE|DEBUG|ERROR
  send_code = true, -- Send code context to the generative AI service? Disable to prevent leaking code outside of Neovim
  silence_notifications = false, -- Silence notifications for actions like saving saving chats?
  use_default_actions = true, -- Use the default actions in the action palette?
})
```

</details>

> [!WARNING]
> Depending on your chosen adapter, you may need to setup environment variables within your shell. See the adapters section below for specific information.

### Adapters

The plugin uses adapters to bridge between generative AI services and the plugin. Currently the plugin supports:

- Anthropic (`anthropic`) - Requires `ANTHROPIC_API_KEY` to be set in your shell
- Ollama (`ollama`)
- OpenAI (`openai`) - Requires `OPENAI_API_KEY` to be set in your shell

You can specify an adapter for each of the strategies in the plugin:

```lua
require("codecompanion").setup({
  adapters = {
    chat = require("codecompanion.adapters").use("openai"),
    inline = require("codecompanion.adapters").use("openai"),
  },
})
```

#### Modifying Adapters

It may be necessary to modify certain parameters of an adapter. In the example below, we're changing the name of the API key that the OpenAI adapter uses by passing in a table to the `use` method:

```lua
require("codecompanion").setup({
  adapters = {
    chat = require("codecompanion.adapters").use("openai", {
      env = {
        api_key = "DIFFERENT_OPENAI_KEY",
      },
    }),
  },
})
```

> [!TIP]
> To create your own adapter please refer to the [ADAPTERS](ADAPTERS.md) guide

### Edgy.nvim Configuration

The author recommends pairing with [edgy.nvim](https://github.com/folke/edgy.nvim) for a Co-Pilot Chat-like experience:

```lua
{
  "folke/edgy.nvim",
  event = "VeryLazy",
  init = function()
    vim.opt.laststatus = 3
    vim.opt.splitkeep = "screen"
  end,
  opts = {
    right = {
      { ft = "codecompanion", title = "Code Companion Chat", size = { width = 0.45 } },
    }
  }
}
```

### Highlight Groups

The plugin sets the following highlight groups during setup:

- `CodeCompanionTokens` - Virtual text showing the token count when in a chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the chat buffer

## :rocket: Usage

The plugin has a number of commands:

- `:CodeCompanion` - Inline code writing and refactoring
- `:CodeCompanionChat` - To open up a new chat buffer
- `:CodeCompanionToggle` - Toggle a chat buffer
- `:CodeCompanionActions` - To open up the action palette window

For an optimum workflow, the plugin author recommendeds the following keymaps:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
```

> [!NOTE]
> For some actions, visual mode allows your selection to be sent directly to the chat buffer or the API itself (in the case of _inline code_ actions).

### The Action Palette

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/b5e2ad2d-c6a2-45a4-a4d0-c118dfaec943" alt="action selector" /></p>

> [!NOTE]
> Please see the [RECIPES](RECIPES.md) guide in order to add your own actions to the palette.

The Action Palette, opened via `:CodeCompanionActions`, contains all of the actions and their associated strategies for the plugin. It's the fastest way to start leveraging CodeCompanion. Depending on whether you're in _normal_ or _visual_ mode will affect the options that are available to you in the palette.

> [!TIP]
> If you wish to turn off the default actions, set `use_default_actions = false` in your config.

### The Chat Buffer

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/84d5e03a-0b48-4ffb-9ca5-e299d41171bd" alt="chat buffer" /></p>

The chat buffer is where you can converse with the generative AI service, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (or "saved"), autocmds trigger the sending of its content to the generative AI service, in the form of prompts. These prompts are segmented by H1 headers, commonly `user`, `system` and `assistant`. When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with the generative AI from within Neovim.

#### Keymaps

When in the chat buffer, there are number of keymaps available to you (which can be changed in the config):

- `<C-s>` - Save the buffer and trigger a response from the generative AI service
- `<C-c>` - Close the buffer
- `q` - Cancel the stream from the API
- `gc` - Clear the buffer's contents
- `ga` - Add a codeblock
- `gs` - Save the chat to disk
- `[` - Move to the next header
- `]` - Move to the previous header

#### Saved Chats

Chat buffers are not saved to disk by default, but can be by pressing `gs` in the buffer. Saved chats can then be restored via the Action Palette and the _Saved chats_ action.

#### Settings

If `display.chat.show_settings` is set to `true`, at the very top of the chat buffer will be the adapter parameters which can be changed to tweak the response back to you. This enables fine-tuning and parameter of the generative AI results throughout the chat. You can find more detail about them by moving the cursor over them.

### Inline Code

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/7e1f2e16-7b6f-453e-b3b0-650f3ac0fc0a" alt="Inline code" /></p>

You can use the plugin to create inline code directly into a Neovim buffer. This can be invoked by using the _Action Palette_ (as above) or from the command line via `:CodeCompanion`. For example:

```
:CodeCompanion create a table of 5 fruits
```

```
:'<,'>CodeCompanion refactor the code to make it more concise
```

> [!NOTE]
> The command can detect if you've made a visual selection and send any code as context to the API alongside the filetype of the buffer.

### In-Built Actions

The plugin comes with a number of [in-built actions](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/actions.lua) which aim to improve your Neovim workflow. Actions make use of either a _chat_ or an _inline_ strategy. The chat strategy opens up a chat buffer whilst an inline strategy will write output from the generative AI service into the Neovim buffer.

#### Chat and Chat as

Both of these actions utilise the `chat` strategy. The `Chat` action opens up a fresh chat buffer. The `Chat as` action allows for persona based context to be set in the chat buffer allowing for better and more detailed responses from the generative AI service.

> [!TIP]
> Both of these actions allow for visually selected code to be sent to the chat buffer as code blocks.

#### Open chats

This action enables users to easily navigate between their open chat buffers. A chat buffer can be deleted (and removed from memory) by pressing `<C-c>`.

#### Inline code

This action utilises the `inline` strategy. This action can be useful for writing inline code in a buffer or even refactoring a visual selection; all based on a user's prompt. The action is designed to write code for the buffer filetype that it is initated in, or, if run from a terminal prompt, to write commands.

The strategy comes with a number of helpers which the user can type in the prompt, similar to [GitHub Copilot Chat](https://github.blog/changelog/2024-01-30-code-faster-and-better-with-github-copilots-new-features-in-visual-studio/):

- `/doc` to add a documentation comment
- `/optimize` to analyze and improve the running time of the selected code
- `/tests` to create unit tests for the selected code

> [!NOTE]
> The options available to the user in the Action Palette will depend on the Vim mode.

#### Code advisor

As the name suggests, this action provides advice on a visual selection of code and utilises the `chat` strategy. The response from the API is streamed into a chat buffer which follows the `display.chat` settings in your configuration.

#### LSP assistant

Taken from the fantastic [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) plugin, this action provides advice on how to correct any LSP diagnostics which are present on the visually selected lines. Again, the `send_code = false` value can be set in your config to prevent the code itself being sent to the generative AI service.

## :rainbow: Helpers

### Hooks / User events

The plugin fires the following events during its lifecycle:

- `CodeCompanionRequest` - Fired during the API request. Outputs `data.status` with a value of `started` or `finished`
- `CodeCompanionChatSaved` - Fired after a chat has been saved to disk
- `CodeCompanionChat` - Fired at various points during the chat buffer. Comes with the following attributes:
  - `data.action = close_buffer` - For when a chat buffer has been permanently closed
  - `data.action = hide_buffer` - For when a chat buffer is hidden
  - `data.action = show_buffer` - For when a chat buffer is visible after being hidden
- `CodeCompanionInline` - Fired during the inline API request alongside `CodeCompanionRequest`. Outputs `data.status` with a value of `started` or `finished`

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline",
  group = group,
  callback = function(request)
    print(request.data.status) -- outputs "started" or "finished"
  end,
})
```

> [!TIP]
> A possible use case is for formatting the buffer after an inline code request

### Heirline.nvim

If you're using the fantastic [Heirline.nvim](https://github.com/rebelot/heirline.nvim) plugin, consider the following snippet to display an icon in the statusline whilst CodeCompanion is conversing with the generative AI service:

```lua
local CodeCompanion = {
  static = {
    processing = false,
  },
  update = {
    "User",
    pattern = "CodeCompanionRequest",
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
