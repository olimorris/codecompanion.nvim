---
description: Getting started with CodeCompanion
---

# Getting Started

> [!IMPORTANT]
> The default adapter in CodeCompanion is [GitHub Copilot](https://docs.github.com/en/copilot/using-github-copilot/copilot-chat/asking-github-copilot-questions-in-your-ide). If you have [copilot.vim](https://github.com/github/copilot.vim) or [copilot.lua](https://github.com/zbirenbaum/copilot.lua) installed then expect CodeCompanion to work out of the box.

This guide is intended to help you get up and running with CodeCompanion and begin your journey of coding with AI in Neovim. It assumes that you have already installed the plugin. If you haven't done so, please refer to the [installation instructions](/installation) first.

## Using the Documentation

Throughout the documentation you will see examples that are wrapped in a `require("codecompanion").setup({ })` block. This is purposefully done so that users can apply them to their own Neovim configuration.

If you're using [lazy.nvim](https://github.com/folke/lazy.nvim), you can simply apply the examples that you see in this documentation in the `opts` table. For example, the following code snippet from these docs:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "anthropic",
      model = "claude-sonnet-4-20250514"
    },
  },
  opts = {
    log_level = "DEBUG",
  },
})
```

can be used in a _lazy.nvim_ configuration like so:

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim"
  },
  opts = {
    interactions = {
      chat = {
        adapter = "anthropic",
        model = "claude-sonnet-4-20250514"
      },
    },
    -- NOTE: The log_level is in `opts.opts`
    opts = {
      log_level = "DEBUG",
    },
  },
},
```

## Interactions

The plugin uses the notion of _interactions_ to describe the many different ways that you can interact with an LLM from within CodeCompanion. There are four main types of interactions:

- **Chat** - A chat buffer where you can converse with an LLM (`:CodeCompanionChat`)
- **Inline** - An inline assistant that can write code directly into a buffer (`:CodeCompanion`)
- **Cmd** - Create Neovim commands in the command-line (`:CodeCompanionCmd`)
- **Background** - Runs tasks in the background such as compacting chat messages or generating titles for chats

## Configuring an Adapter

> [!NOTE]
> The adapters that the plugin supports out of the box can be found [here](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters). Or, see the user contributed adapters [here](configuration/adapters-http#community-adapters)

An adapter is what connects Neovim to an LLM (via _HTTP_) or an agent (via [ACP](https://agentclientprotocol.com/overview/introduction)). It's the interface that allows data to be sent, received and processed. In order to use the plugin, you need to make sure you've configured an adapter first:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      -- You can specify an adapter by name and model
      adapter = {
        name = "copilot",
        model = "gpt-4.1",
      },
    },
    -- Or just specify the adapter by name
    inline = {
      adapter = "anthropic",
    },
    cmd = {
      adapter = "openai",
    },
    background = {
      adapter = {
        name = "ollama",
        model = "qwen-7b-instruct",
      },
    },
  },
})
```

In the example above, we're using the Copilot adapter for the chat interaction and the Anthropic one for the inline. You can mix and match as you see fit.

> [!IMPORTANT]
> [ACP adapters](/configuration/adapters-acp) are only supported for the chat interction.

There are two "types" of adapter in CodeCompanion; [HTTP](/configuration/adapters-http) adapters which connect you to an LLM and [ACP](/configuration/adapters-acp) adapters which leverage the [Agent Client Protocol](https://agentclientprotocol.com) to connect you to an agent.

Refer to the respective sections to understand more about working with adapters that enable agents like [Claude Code](/configuration/adapters-acp#setup-claude-code).

### Setting an API Key

Because most LLMs require an API key, you'll need to share that with the adapter. By default, adapters will look in your environment for a `*_API_KEY` where `*` is the name of the adapter such as `ANTHROPIC` or `OPENAI`. Refer to the documentation of the LLM or agent you're using to find out what the environment variable is called.

You can extend an adapter and change the API key like so:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            api_key = "MY_OTHER_ANTHROPIC_KEY",
          },
        })
      end,
    },
  },
})
```

There are numerous ways that environment variables can be set for adapters. Refer to the [environment variables](/configuration/adapters-http#environment-variables) section for more information.

## Chat Buffer

<p align="center">
  <img src="https://github.com/user-attachments/assets/597299d2-36b3-469e-b69c-4d8fd14838f8" alt="Chat buffer">
</p>

The Chat Buffer is where you can converse with an LLM from within Neovim. It operates on a single response per turn, basis. Once your adapter has been configured, you can start using the chat buffer and begin interacting with an LLM.

Run `:CodeCompanionChat` to open a chat buffer. Type your prompt and send it by pressing `<C-s>` while in insert mode or `<CR>` in normal mode. Alternatively, run `:CodeCompanionChat why are Lua and Neovim so perfect together?` to open the chat buffer and send a prompt at the same time. Toggle the chat buffer with `:CodeCompanionChat Toggle`.

You can add context from your code base by using _Variables_ and _Slash Commands_ in the chat buffer.

> [!IMPORTANT]
> As of `v17.5.0`, variables and tools are now wrapped in curly braces, such as `#{buffer}` or `@{files}`

### Variables

_Variables_, accessed via `#`, contain data about the present state of Neovim. You can find a list of available variables, [here](/usage/chat-buffer/variables.html). The buffer variable will automatically link a buffer to the chat buffer, by default, updating the LLM when the buffer changes.

> [!TIP]
> Use them in your prompt like: `What does the code in #{buffer} do?`

### Slash Commands

> [!IMPORTANT]
> These have been designed to work with native Neovim completions alongside nvim-cmp and blink.cmp. To open the native completion menu use `<C-_>` in insert mode when in the chat buffer. Note: Slash commands should also work with coc.nvim.

_Slash commands_, accessed via `/`, run commands to insert additional context into the chat buffer. You can find a list of available commands as well as how to use them, [here](/usage/chat-buffer/slash-commands.html).

### Tools

_Tools_, accessed via `@`, allow the LLM to function as an agent and leverage external tools. You can find a list of available tools as well as how to use them, [here](usage/chat-buffer/tools.html#available-tools).

> [!TIP]
> Use them in your prompt like: `Can you use the @{grep_search} tool to find occurrences of "add_message"`

## Inline Assistant

<p align="center">
  <video controls muted src="https://github.com/user-attachments/assets/11a42705-d9de-4eb5-a9ab-c8a2772fb4d4"></video>
</p>

> [!NOTE]
> The diff provider in the video is [mini.diff](https://github.com/echasnovski/mini.diff)

The inline assistant enables an LLM to write code directly into a Neovim buffer.

Run `:CodeCompanion your prompt` to call the inline assistant. The assistant will evaluate the prompt and either write code or open a chat buffer. You can also make a visual selection and call the assistant. To send additional context alongside your prompt, you can leverage [variables](/usage/inline-assistant#variables) such as `:CodeCompanion #{buffer} <your prompt>`.

For convenience, you can call prompts with their `alias` from the [prompt library](https://github.com/olimorris/codecompanion.nvim/blob/6a4341a4cfe8988a57ad9e8b7dc01ccd6f3e1628/lua/codecompanion/config.lua#L565) such as `:'<,'>CodeCompanion /explain`. The prompt library comes with the following presets:

- `/commit` - Generate a commit message
- `/explain` - Explain how selected code in a buffer works
- `/fix` - Fix the selected code
- `/lsp` - Explain the LSP diagnostics for the selected code
- `/tests` - Generate unit tests for selected code

## Commands

Use CodeCompanion to create Neovim commands in command-line mode (`:h Command-line`) via `:CodeCompanionCmd <your prompt>`.

## Action Palette

<p align="center">
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" alt="Action Palette">
</p>

Run `:CodeCompanionActions` to open the action palette, which gives you access to the plugin's features, including your prompts from the [prompt library](/configuration/prompt-library).

By default the plugin uses `vim.ui.select`, however, you can change the provider by altering the `display.action_palette.provider` config value to be `telescope`, `mini_pick`  or `snacks`. You can also call the Telescope extension with `:Telescope codecompanion`.

> [!NOTE]
> Some actions and prompts will only be visible if you're in _Visual mode_.

## List of Commands

The plugin has four core commands:

- `CodeCompanion` - Open the inline assistant
- `CodeCompanionChat` - Open a chat buffer
- `CodeCompanionCmd` - Generate a command in the command-line
- `CodeCompanionActions` - Open the _Action Palette_

However, there are multiple options available:

- `CodeCompanion <prompt>` - Prompt the inline assistant
- `CodeCompanion adapter=<adapter> <prompt>` - Prompt the inline assistant with a specific adapter
- `CodeCompanion /<prompt library>` - Call an item from the [prompt library](configuration/prompt-library)
- `CodeCompanionChat <prompt>` - Send a prompt to the LLM via a chat buffer
- `CodeCompanionChat adapter=<adapter> model=<model>` - Open a chat buffer with a specific adapter and model
- `CodeCompanionChat Add` - Add visually selected chat to the current chat buffer
- `CodeCompanionChat RefreshCache` - Used to refresh conditional elements in the chat buffer
- `CodeCompanionChat Toggle` - Toggle a chat buffer

## Suggested Plugin Workflow

For an optimum plugin workflow, I recommend the following:

```lua
vim.keymap.set({ "n", "v" }, "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<LocalLeader>a", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
vim.keymap.set("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
```

> [!NOTE]
> You can also assign prompts from the library to specific mappings. See the [prompt library](configuration/prompt-library#assigning-prompts-to-a-keymap) section for more information.
