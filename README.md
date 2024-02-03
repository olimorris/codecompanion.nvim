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
  <p><strong>Chat buffer</strong><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/a19c8397-a1e2-44df-98be-8a1b4d307ea7" alt="chat buffer" /></p>
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
    "nvim-lua/plenary.nvim",
    {
      "stevearc/dressing.nvim", -- Optional: Improves the default Neovim UI
      opts = {},
    },
  },
  cmd = { "CodeCompanionToggle", "CodeCompanionActions" },
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

> **Note**: You only need to the call the `setup` function if you wish to change any of the defaults.

<details>
  <summary>Click to see the default configuration</summary>

```lua
{
  api_key = "OPENAI_API_KEY", -- Your API key
  org_api_key = "OPENAI_ORG_KEY", -- Your organisation API key
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
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/conversations", -- Path to save conversations to
  },
  display = {
    action_palette = {
      width = 95,
      height = 10,
    },
    chat = { -- Options for the chat strategy
      type = "buffer", -- buffer|float
      show_settings = false, -- Show the model settings in the chat window
      float = {
        border = "single",
        max_height = 0,
        max_width = 0,
        padding = 1,
      },
    },
    win_options = {
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
  keymaps = {
    ["<C-c>"] = "keymaps.close", -- Close the chat buffer
    ["q"] = "keymaps.cancel_request", -- Cancel the currently streaming request
    ["gc"] = "keymaps.clear", -- Clear the contents of the chat
    ["ga"] = "keymaps.codeblock", -- Insert a codeblock in the chat
    ["gs"] = "keymaps.save_conversation", -- Save the current chat as a conversation
    ["]"] = "keymaps.next", -- Move to the next header in the chat
    ["["] = "keymaps.previous", -- Move to the previous header in the chat
  },
  log_level = "ERROR", -- TRACE|DEBUG|ERROR
  send_code = true, -- Send code context to the API?
  show_token_count = true, -- Show the token count for the current chat?
  use_default_actions = true, -- Use the default actions in the action palette?
}
```

</details>

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

The plugin sets a number of highlights during setup:

- `CodeCompanionTokens` - Virtual text showing the token count when in a chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the chat buffer

## :rocket: Usage

The plugin has a number of commands:

- `CodeCompanionChat` - To open up a new chat buffer
- `CodeCompanionToggle` - Toggle a chat buffer
- `CodeCompanionActions` - To open up the action palette window

For an optimum workflow, the plugin author recommendeds the following keymaps:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
```

> **Note**: For some actions, visual mode allows your selection to be sent directly to the chat buffer or the API itself (in the case of `author` actions).

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

The chat buffer is where you can converse with your GenAI API, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (or "saved"), autocmds trigger the sending of its content to the API, in the form of prompts. These prompts are segmented by H1 headers: `user` and `assistant` (see OpenAI's [Chat Completions API](https://platform.openai.com/docs/guides/text-generation/chat-completions-api) for more on this). When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with GenAI, from within Neovim.

#### Keymaps

When in the chat buffer, there are number of keymaps available to you (which can be changed in the config):

- `<C-c>` - Close the buffer
- `q` - Cancel streaming from the API
- `gc` - Clear the buffer's contents
- `ga` - Add a codeblock
- `gs` - Save the chat as a conversation
- `[` - Move to the next header in the buffer
- `]` - Move to the previous header in the buffer

#### Conversations

Chat Buffers are not automatically saved to disk, owing to them being an `acwrite` buftype (see `:h buftype`). However, the plugin allows for this via the notion of Conversations and pressing `gs` in the buffer. Conversations can then be restored via the Action Palette and the _Load conversations_ action.

#### Settings

If `display.chat.show_settings` is set to `true`, at the very top of the chat buffer will be the parameters which can be changed to affect the API's response back to you. This enables fine-tuning and parameter tweaking throughout the chat. You can find more detail about them by moving the cursor over them or referring to the [Chat Completions reference guide](https://platform.openai.com/docs/api-reference/chat) if you're using OpenAI.

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

As the name suggests, this action provides advice on a visual selection of code and utilises the `advisor` strategy. The response from the API is output into a chat buffer which follows the `display.chat` settings in your configuration.

> **Note**: For some users, the sending of code to the GenAI may not be an option. In those instances, you can set `send_code = false` in your config.

#### LSP assistant

Taken from the fantastic [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) plugin, this action provides advice (utilising the `advisor` strategy) on any LSP diagnostics which occur across visually selected lines and how they can be fixed. Again, the `send_code = false` value can be set in your config to only send diagnostic messages to OpenAI.

## :rainbow: Helpers

### Hooks / User events

The plugin fires the following events during its lifecycle:

- `CodeCompanionRequest` - Fired during the API request. Outputs `data.status` with a value of `started` or `finished`
- `CodeCompanionConversation` - Fired after a conversation has been saved to disk
- `CodeCompanionChat` - Fired at various points during the chat buffer. Comes with the following attributes:
  - `data.action = close_buffer` - For when a chat buffer has been permanently closed
  - `data.action = hide_buffer` - For when a chat buffer is now hidden
  - `data.action = show_buffer` - For when a chat buffer is now visible after being hidden

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionRequest",
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
local GenAI = {
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
