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
  <p>https://github.com/user-attachments/assets/1375f623-c088-4bf0-a5d7-8d81eaa3a94b</p>
  <p>https://github.com/user-attachments/assets/8ae255ba-1f5c-470c-a252-f31d056297c3</p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- The `curl` library installed
- Neovim 0.9.2 or greater
- _(Optional)_ An API key for your chosen LLM

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
> To create your own adapter please refer to the [ADAPTERS](doc/ADAPTERS.md) guide.

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
    llama3 = function()
      return require("codecompanion.adapters").use("ollama", {
        name = "llama3", -- Ensure the model is differentiated from Ollama
        schema = {
          model = {
            default = "llama3:latest",
          },
          num_ctx = {
            default = 16384,
          },
          num_predict = {
            default = -1,
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

- `CodeCompanionChatHeader` - The headers in the chat buffer
- `CodeCompanionChatSeparator` - Separator between headings in the chat buffer
- `CodeCompanionChatTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionChatTool` - Tools in the chat buffer
- `CodeCompanionChatVariable` - Variables in the chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the plugin

> [!TIP]
> You can change which highlight group these link to in your configuration.

## :rocket: Getting Started

**Inline Prompting**

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/user-attachments/assets/bf88836d-832d-4f69-a58e-371bbb8b9bd2</p>
</div>

<!-- panvimdoc-ignore-end -->

To start interacting with the plugin you can run `:CodeCompanion <your prompt>` from the command line. You can also make a visual selection in Neovim and run `:'<,'>CodeCompanion <your prompt>` to send it as context. The plugin will initially use an LLM to classify your prompt in order to determine where in Neovim to place the response. You can find more about the classificiations in the [inline prompting](#inline-prompting) section.

For convenience, you can also call [default prompts](#default-prompts) from the command line via slash commands:

- `/explain` - Explain how selected code in a buffer works
- `/tests` - Generate unit tests for selected code
- `/fix` - Fix the selected code
- `/buffer` - Send the current buffer to the LLM alongside a prompt
- `/lsp` - Explain the LSP diagnostics for the selected code
- `/commit` - Generate a commit message

Running `:'<,'>CodeCompanion /fix` will trigger the plugin to start following the fix prompt as defined in the [config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua). Some of the slash commands can also take custom prompts. For example, running `:'<,'>CodeCompanion /buffer refactor this code` sends the whole buffer as context alongside a prompt to refactor the selected code.

There are also keymaps available to accept or reject edits from the LLM in the [inline prompting](#inline-prompting) section.

**Chat Buffer**

<!-- panvimdoc-ignore-start -->

<p align="center"><img src="https://github.com/user-attachments/assets/6097fa93-906c-4ed1-b1c4-8b52ad151f9f" alt="Chat buffer"></p>

<!-- panvimdoc-ignore-end -->

The chat buffer is where you'll likely spend most of your time when interacting with the plugin. Running `:CodeCompanionChat` or `:'<,'>CodeCompanionChat` will open up a chat buffer where you can converse directly with an LLM. As a convenience, you can use `:CodeCompanionToggle` to toggle the visibility of a chat buffer.

When in the chat buffer you have access to the following variables:

- `#buffer` - Share the current buffer's content with the LLM. You can also specify line numbers with `#buffer:8-20`
- `#buffers` - Share all current open buffers with the LLM
- `#editor` - Share the buffers and lines that you see in the editor's viewport
- `#lsp` - Share LSP information and code for the current buffer

> [!NOTE]
> When in the chat buffer, the `?` keymap brings up all of the available keymaps, variables and tools available to you.

**Agents / Tools**

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/user-attachments/assets/8bc083c7-f4f1-4eab-b9fe-ab6c4c30ee91</p>
</div>

<!-- panvimdoc-ignore-end -->

The plugin also supports LLMs acting as agents by the calling of external tools. In the video above, we're asking an LLM to execute the contents of the buffer via the _@code_runner_ tool, all from within a chat buffer.

When in the chat buffer you have access to the following tools:

- `@code_runner` - The LLM can trigger the running of any code from within a Docker container
- `@rag` - The LLM can browse and search the internet for real-time information to supplement its response
- `@buffer_editor` - The LLM can edit code in a Neovim buffer by searching and replacing blocks

> [!IMPORTANT]
> Agents are currently at an alpha stage right now and I'm using the term agent and tool interchangeably.

**Action Palette**

<!-- panvimdoc-ignore-start -->

<p align="center"><img src="https://github.com/user-attachments/assets/23c2ba7c-d438-4132-b13f-11c51ce0a2c5" alt="Action Palette"></p>

<!-- panvimdoc-ignore-end -->

The `:CodeCompanionActions` command will open the _Action Palette_, giving you access to all of the functionality in the plugin. The _Prompts_ section is where the default prompts and your custom ones can be accessed from. You'll notice that some prompts have a slash command in their description such as `/commit`. This enables you to trigger them from the command line by doing `:CodeCompanion /commit`. Some of these prompts also have keymaps assigned to them (which can be overwritten!) which offers an even easier route to triggering them.

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

A [RECIPES](doc/RECIPES.md) guide has been created to show you how you can add your own prompts to the _Action Palette_.

### The Chat Buffer

The chat buffer is where you can converse with an LLM, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (or "saved"), autocmds trigger the sending of its content to the LLM in the form of prompts. These prompts are segmented by H1 headers: `user`, `system` and `assistant`. When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with your LLM from within Neovim.

As noted in the [Getting Started](#rocket-getting-started) section, there are a number of variables that you can make use of whilst in the chat buffer. Use `#` to bring up the completion menu to see the available options.

**Keymaps**

When in the chat buffer, there are number of keymaps available to you:

- `?` - Bring up the help menu
- `<CR>`|`<C-s>` - Send the buffer to the LLM
- `<C-c>` - Close the buffer
- `q` - Cancel the request from the LLM
- `ga` - Change the adapter
- `gx` - Clear the buffer's contents
- `gx` - Add a codeblock
- `gs` - Save the chat to disk
- `}` - Move to the next chat
- `{` - Move to the previous chat
- `[` - Move to the next header
- `]` - Move to the previous header

**Saved Chats**

Chat buffers are not saved to disk by default, but can be by pressing `gs` in the buffer. Saved chats can then be restored via the Action Palette and the _Load saved chats_ action.

**Settings**

If `display.chat.show_settings` is set to `true`, at the very top of the chat buffer will be the adapter's model parameters which can be changed to tweak the response from the LLM. You can find more detail by moving the cursor over them.

**Open Chats**

From the Action Palette, the `Open Chats` action enables users to easily navigate between their open chat buffers. A chat buffer can be deleted (and removed from memory) by pressing `<C-c>`.

### Inline Prompting

> [!NOTE]
> If `send_code = false` then this will take precedent and no code will be sent to the LLM

Inline prompts can be triggered via the `CodeCompanion <your prompt>` command. As mentioned in the [Getting Started](#rocket-getting-started) section, you can also leverage visual selections and slash commands like `'<,'>CodeCompanion /buffer what does this code do?`, where the slash command points to a [default prompt](#default-prompts) and any words after that act as a custom prompt to the LLM.

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed after the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to overwrite a visual selection. The plugin will use the inline LLM you've specified in your config to determine if the response should follow any of the placements below:

- _after_ - after the visual selection/cursor
- _before_ - before the visual selection/cursor
- _new_ - in a new buffer
- _replace_ - replacing the visual selection
- _chat_ - in a chat buffer

There are also keymaps available to you after an inline edit has taken place:

- `ga` - Accept an inline edit
- `gr` - Reject an inline edit

### Default Prompts

> [!NOTE]
> Please see the [RECIPES](doc/RECIPES.md) guide in order to add your own prompts to the Action Palette and as a slash command.

The plugin comes with a number of default prompts ([as per the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua)) which can be called via keymaps and/or slash commands. These prompts have been carefully curated to mimic those in [GitHub's Copilot Chat](https://docs.github.com/en/copilot/using-github-copilot/asking-github-copilot-questions-in-your-ide).

### Agents / Tools

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, agents are simply context that's given to an LLM via a `system` prompt. This gives it knowledge and a defined schema which it can include in its response for the plugin to parse, execute and feedback on. Agents can be added as a participant in a chat buffer by using the `@` key.

More information on how agents work and how you can create your own can be found in the [AGENTS](doc/AGENTS.md) guide.

### Workflows

> [!WARNING]
> Workflows may result in the significant consumption of tokens if you're using an external LLM.

As [outlined](https://www.deeplearning.ai/the-batch/issue-242/) by Andrew Ng, agentic workflows have the ability to dramatically improve the output of an LLM. Infact, it's possible for older models like GPT 3.5 to outperform newer models (using traditional zero-shot inference). Andrew [discussed](https://www.youtube.com/watch?v=sal78ACtGTc&t=249s) how an agentic workflow can be utilised via multiple prompts that invoke the LLM to self reflect. Implementing Andrew's advice, the plugin supports this notion via the use of workflows. At various stages of a pre-defined workflow, the plugin will automatically prompt the LLM without any input or triggering required from the user.

Currently, the plugin comes with the following workflows:

- Adding a new feature
- Refactoring code

Of course you can add new workflows by following the [RECIPES](doc/RECIPES.md) guide.

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
