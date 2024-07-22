<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/e54f98b6-8bfd-465a-85b6-73ab6bb274fa" alt="CodeCompanion.nvim" />
</p>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/issues"><img src="https://img.shields.io/github/issues/olimorris/codecompanion.nvim?color=%23d19a66&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/blob/main/LICENSE"><img src="https://img.shields.io/github/license/olimorris/codecompanion.nvim?style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
</p>

<p align="center">
Currently supports: Anthropic, Ollama and OpenAI adapters
</p>

> [!IMPORTANT]
> This plugin is provided as-is and is primarily developed for my own workflows. As such, I offer no guarantees of regular updates or support and I expect the plugin's API to change regularly. Bug fixes and feature enhancements will be implemented at my discretion, and only if they align with my personal use-cases. Feel free to fork the project and customize it to your needs, but please understand my involvement in further development will be intermittent. To be notified of breaking changes in the plugin, please subscribe to [this issue](https://github.com/olimorris/codecompanion.nvim/issues/9).

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5e5a5e54-c1d9-4fe2-8ae0-1cfbfdd6cea5" alt="Header" />
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: A Copilot Chat experience in Neovim
- :electric_plug: Support for OpenAI, Anthropic and Ollama
- :rocket: Inline code creation and refactoring
- :robot: Variables, Agents and Workflows to improve LLM output
- :sparkles: Built in prompts for LSP errors and code advice
- :building_construction: Create your own custom prompts for Neovim
- :floppy_disk: Save and restore your chats
- :muscle: Async execution for improved performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p>https://github.com/user-attachments/assets/575fc091-8188-4e39-9d04-a8d47c9e8c52</p>
  <p>https://github.com/user-attachments/assets/cddd2ccd-f60d-4630-88fd-36a2e5a89783</p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- The `curl` library installed
- Neovim 0.9.2 or greater
- _(Optional)_ An API key for your chosen LLM
- _(Optional)_ The `base64` library installed

## :package: Installation

Install the plugin with your preferred package manager:

**[Lazy.nvim](https://github.com/folke/lazy.nvim)**

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "nvim-telescope/telescope.nvim", -- Optional
    {
      "stevearc/dressing.nvim", -- Optional: Improves the default Neovim UI
      opts = {},
    },
  },
  config = true
}
```

**[Packer](https://github.com/wbthomason/packer.nvim)**

```lua
use({
  "olimorris/codecompanion.nvim",
  config = function()
    require("codecompanion").setup()
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "nvim-telescope/telescope.nvim", -- Optional
    "stevearc/dressing.nvim" -- Optional: Improves the default Neovim UI
  }
})
```

## :gear: Configuration

The default configuration can be found in the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file. You can change any of the defaults by calling the `setup` function. For example:

```lua
require("codecompanion").setup({
  opts = {
    send_code = false
  }
})
```

**Adapters**

> [!WARNING]
> Depending on your [chosen adapter](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters), you may need to set an API key.

The plugin uses adapters to connect the plugins to LLMs. Currently the plugin supports:

- Anthropic (`anthropic`) - Requires an API key
- Ollama (`ollama`)
- OpenAI (`openai`) - Requires an API key

Strategies are the different ways that a user can interact with the plugin. The _chat_ and _agent_ strategies harness a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

To specify a different adapter to the defaults, simply change the `strategies.*` table:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "ollama",
    },
    inline = {
      adapter = "ollama",
    },
    agent = {
      adapter = "anthropic",
    },
  },
})
```

> [!TIP]
> To create your own adapter please refer to the [ADAPTERS](docs/ADAPTERS.md) guide.

**Configuring environment variables**

You can customise an adapter's configuration as follows:

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = function()
      return require("codecompanion.adapters").use("anthropic", {
        env = {
          api_key = "ANTHROPIC_API_KEY_1"
        },
      })
    end,
  },
  strategies = {
    chat = {
      adapter = "anthropic",
    },
  },
})
```

In the example above, we're using the base of the Anthropic adapter but changing the name of the default API key which it uses.

Having API keys in plain text in your shell is not always safe. Thanks to [this PR](https://github.com/olimorris/codecompanion.nvim/pull/24), you can run commands from within the configuration:

```lua
require("codecompanion").setup({
  adapters = {
    openai = function()
      return require("codecompanion.adapters").use("openai", {
        env = {
          api_key = "cmd:op read op://personal/OpenAI/credential --no-newline",
        },
      })
    end,
    strategies = {
      chat = {
        adapter = "openai",
      },
    },
  },
})
```

In this example, we're using the 1Password CLI to read an OpenAI credential.

**Configuring adapter settings**

LLMs have many settings such as _model_, _temperature_ and _max_tokens_. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = function()
      return require("codecompanion.adapters").use("anthropic", {
        schema = {
          model = {
            default = "claude-3-sonnet-20240229",
          },
        },
      })
    end,
  },
})
```

> [!TIP]
> Refer to your chosen [adapter](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters) to see the settings available.

**Highlight Groups**

The plugin sets the following highlight groups during setup:

- `CodeCompanionTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionVirtualText` - All other virtual text in the chat buffer
- `CodeCompanionVirtualTextAgents` - Virtual text in the chat buffer for when a agent is running
- `CodeCompanionChatVariable` - Variables in the chat buffer

> [!TIP]
> You can change which highlight group these link to in your configuration.

## :rocket: Getting Started

**Inline Prompting**

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/user-attachments/assets/c2ddf272-ae50-4500-9003-44d30e806b4e</p>
</div>

<!-- panvimdoc-ignore-end -->

To start interacting with the plugin you can run `:CodeCompanion <your prompt>` from the command line. You can also make a visual selection in Neovim and run `:'<,'>CodeCompanion <your prompt>` to send it as context. A command such as `:'<,'>CodeCompanion what does this code do?` will prompt the LLM the respond in a chat buffer allowing you to ask any follow up questions. Whereas a command such as `:CodeCompanion can you create a function that outputs the current date and time` would result in the output being placed at the cursor's position in the buffer.

In the video, you'll notice that we're triggering a pre-defined advice prompt by running `:'<,'>:CodeCompanion /advice`. You can find more on this in the [default prompts](#default-prompts) section.

**Chat Buffer**

<!-- panvimdoc-ignore-start -->

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5349c177-2fb2-4c00-9c06-194767a9cf6e" alt="Chat buffer"></p>

<!-- panvimdoc-ignore-end -->

The chat buffer is where you'll likely spend most of your time when interacting with the plugin. Running `:CodeCompanionChat` or `:'<,'>CodeCompanionChat` will open up a chat buffer where you can converse directly with an LLM. As a convenience, you can use `:CodeCompanionToggle` to toggle the visibility of a chat buffer.

When in the chat buffer you can include variables in your message such as:

- `#buffer` - To share the contents of the current buffer
- `#buffers` - To share the contents of all loaded buffers that match the filetype of the current buffer
- `#editor` - To share the visible code from all buffers in the editor's viewport

There are also many keymaps you can leverage in the chat buffer which are covered in the [chat buffer section](#the-chat-buffer) of this readme.

**Action Palette**

<!-- panvimdoc-ignore-start -->

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/efb7013e-6c73-48fe-bd79-cdc233dfdc61" alt="Action Palette"></p>

<!-- panvimdoc-ignore-end -->

The `:CodeCompanionActions` command will open the _Action Palette_, giving you access to all of the functionality in the plugin. The _Prompts_ section is where your custom prompts and the pre-defined ones can be accessed. You'll notice that some prompts have a label in their description such as `/commit`. This enables you to trigger them from the command line by doing `:CodeCompanion /commit`. Some of these prompts also have keymaps assigned to them (which can be overwritten!) which offers an even easier route to triggering them.

> [!NOTE]
> Some actions will only be visible in the _Action Palette_ if you're in Visual mode.

**List of commands**

Below is the full list of commands that are available in the plugin:

- `CodeCompanionActions` - To open the _Action Palette_
- `CodeCompanion` - Inline prompting of the plugin
- `CodeCompanion <slash_cmd>` - Inline prompting of the plugin with a slash command e.g. `/commit`
- `CodeCompanionChat` - To open up a new chat buffer
- `CodeCompanionChat <adapter>` - To open up a new chat buffer with a specific adapter
- `CodeCompanionToggle` - To toggle a chat buffer
- `CodeCompanionAdd` - To add visually selected chat to the current chat buffer

**Suggested workflow**

For an optimum workflow, I recommend the following options:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "ga", "<cmd>CodeCompanionAdd<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
```

## :bulb: Advanced Usage

### Customising the Action Palette

A [RECIPES](docs/RECIPES.md) guide has been created to show you how you can add your own prompts to the _Action Palette_.

### The Chat Buffer

The chat buffer is where you can converse with an LLM, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (or "saved"), autocmds trigger the sending of its content to the LLM in the form of prompts. These prompts are segmented by H1 headers: `user`, `system` and `assistant`. When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with your LLM from within Neovim.

**Keymaps**

When in the chat buffer, there are number of keymaps available to you:

- `<C-s>` - Save the buffer and trigger a response from the LLM
- `<C-c>` - Close the buffer
- `q` - Cancel the stream from the LLM
- `gc` - Clear the buffer's contents
- `ga` - Add a codeblock
- `gs` - Save the chat to disk
- `gt` - Add an agent to an existing chat
- `[` - Move to the next header
- `]` - Move to the previous header

**Saved Chats**

Chat buffers are not saved to disk by default, but can be by pressing `gs` in the buffer. Saved chats can then be restored via the Action Palette and the _Load saved chats_ action.

**Settings**

If `display.chat.show_settings` is set to `true`, at the very top of the chat buffer will be the adapter's model parameters which can be changed to tweak the response. You can find more detail about them by moving the cursor over them.

**Open Chats**

From the Action Palette, the `Open Chats` action enables users to easily navigate between their open chat buffers. A chat buffer can be deleted (and removed from memory) by pressing `<C-c>`.

### Inline Prompting

> [!NOTE]
> If `send_code = false` then this will take precedent and no buffers will be sent to the LLM

Inline prompts can be triggered via the `CodeCompanion <your prompt>` command. As mentioned in the [Getting Started](#rocket-getting-started) guide, you can also leverage visual selections and slash commands like `'<,'>CodeCompanion /lsp`.

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed after the cursor's current position in the buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to overwrite a visual selection. The plugin will use the inline LLM you've specified to determine if the response should follow any of the placements below:

- _after_ - after the visual selection/cursor
- _before_ - before the visual selection/cursor
- _new_ - in a new buffer
- _replace_ - replacing the visual selection
- _chat_ - in a chat buffer

### Default Prompts

> [!NOTE]
> Please see the [RECIPES](docs/RECIPES.md) guide in order to add your own pre-defined prompts to the palette.

The plugin comes with a number of default prompts and corresponding keymaps/commands:

- **Custom Prompt** - For custom inline prompting of an LLM (`<LocalLeader>cc`)
- **Senior Developer** - Chat with a senior developer for the given filetype (`<LocalLeader>ce`)
- **Code Advisor** - Get advice from an LLM on code you've selected (`<LocalLeader>ca` / `/advice`)
- **Buffer selection** - Send the current buffer to the LLM alongside a prompt (`<LocalLeader>cb` / `/buffer`)
- **Explain LSP Diagnostics** - Use an LLM to explain LSP diagnostics for code you've selected (`<LocalLeader>cl` / `/lsp`)
- **Generate a Commit Message** - Use an LLM to write a commit message for you (`<LocalLeader>cm` / `/commit`)

Slash Commands can be accessed via the command line by typing `:CodeCompanion /commit`.

### Agents

<!-- panvimdoc-ignore-start -->

<p>https://github.com/olimorris/codecompanion.nvim/assets/9512444/a19229b1-36b2-43b0-ad87-600da06b371e</p>

<!-- panvimdoc-ignore-end -->

> [!IMPORTANT]
> Agents are currently at an alpha stage. I'm yet to properly battle test them so feedback is much appreciated.

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In this plugin, agents are simply context that's given to an LLM via a `system` prompt. This gives it knowledge and a defined schema which it can include in its response for the plugin to parse, execute and feedback on. Agents can be leveraged by opening up the action palette and choosing the _Agents_ option. Or, agents can be added when in an existing chat buffer via the `gt` keymap.

**Agent types**

Currently, there are two types of agent that are supported in the plugin:

- _Command_ -These agents execute a series of shell commands or external scripts.
- _Function_ - These agents perform actions directly within Neovim, interacting closely with buffers and the editor environment.

**Built-in Agents**

- _Code Runner_ - A command-based agent that runs code generated by the LLM using Docker.
- _RAG (Retrieval-Augmented Generation)_ - A command-based agent that supplements the LLM with real-time information.
- _Buffer Editor_ - A function-based agent that edits code by searching and replacing blocks directly within Neovim buffers. This agent showcases a new, more flexible approach to agent implementation, allowing for complex operations that interact closely with the editor.

More information on how agents work and how you can create your own can be found in the [AGENTS](docs/AGENTS.md) guide.

### Workflows

> [!WARNING]
> Workflows may result in the significant consumption of tokens if you're using an external LLM.

As [outlined](https://www.deeplearning.ai/the-batch/issue-242/) by Andrew Ng, agentic workflows have the ability to dramatically improve the output of an LLM. Infact, it's possible for older models like GPT 3.5 to outperform newer models (using traditional zero-shot inference). Andrew [discussed](https://www.youtube.com/watch?v=sal78ACtGTc&t=249s) how an agentic workflow can be utilised via multiple prompts that invoke the LLM to self reflect. Implementing Andrew's advice, the plugin supports this notion via the use of workflows. At various stages of a pre-defined workflow, the plugin will automatically prompt the LLM without any input or triggering required from the user.

Currently, the plugin comes with the following workflows:

- Adding a new feature
- Refactoring code

Of course you can add new workflows by following the [RECIPES](docs/RECIPES.md) guide.

## :lollipop: Extras

**Hooks / User events**

The plugin fires the following events during its lifecycle:

- `CodeCompanionRequest` - Fired during the API request. Outputs `data.status` with a value of `started` or `finished`
- `CodeCompanionChatSaved` - Fired after a chat has been saved to disk
- `CodeCompanionChat` - Fired at various points during the chat buffer. Comes with the following attributes:
  - `data.action = hide_buffer` - For when a chat buffer is hidden
- `CodeCompanionInline` - Fired during the inline API request alongside `CodeCompanionRequest`. Outputs `data.status` with a value of `started` or `finished` and `data.placement` with the placement of the text from the LLM
- `CodeCompanionAgent` - Fired when an agent is running. Outputs `data.status` with a value of `started` or `success`/`failure`

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline",
  group = group,
  callback = function(args)
    if args.data.status == "finished" then
      -- Format the buffer after the inline request has completed
      require("conform").format({ bufnr = args.buf })
    end
  end,
})
```

**Statuslines**

You can incorporate a visual indication to show when the plugin is communicating with an LLM in your Neovim configuration. Below are examples for two popular statusline plugins.

_lualine.nvim:_

```lua
local M = require("lualine.component"):extend()

M.processing = false
M.spinner_index = 1

local spinner_symbols = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}
local spinner_symbols_len = 10

-- Initializer
function M:init(options)
  M.super.init(self, options)

  local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "CodeCompanionRequest",
    group = group,
    callback = function(request)
      self.processing = (request.data.status == "started")
    end,
  })
end

-- Function that runs every time statusline is updated
function M:update_status()
  if self.processing then
    self.spinner_index = (self.spinner_index % spinner_symbols_len) + 1
    return spinner_symbols[self.spinner_index]
  else
    return nil
  end
end

return M
```

_heirline.nvim:_

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

**Legendary.nvim**

The plugin also supports the amazing [legendary.nvim](https://github.com/mrjones2014/legendary.nvim) plugin. Simply enable it in your config:

```lua
require('legendary').setup({
  extensions = {
    codecompanion = true,
  },
})
```

<!-- panvimdoc-ignore-start -->

## :gift: Contributing

I am open to contributions but they will be implemented at my discretion. Feel free to open up a discussion before embarking on a big PR and please make sure you've read the [CONTRIBUTING.md](CONTRIBUTING.md) guide.

## :clap: Acknowledgements

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer and his feedback
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action
- [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) for the calculation of tokens

<!-- panvimdoc-ignore-end -->
