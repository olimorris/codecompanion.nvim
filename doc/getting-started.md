---
description: "Get up and running with CodeCompanion in Neovim — configure your first LLM adapter, open a chat buffer, use the inline interaction, and learn the core commands."
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

The plugin uses the notion of _interactions_ to describe the many different ways that you can interact with an Agent or LLM from within CodeCompanion. There are five main types of interactions:

- **Chat** - A chat buffer where you can converse with an LLM (`:CodeCompanionChat`)
- **CLI** - A terminal wrapper around agent CLI tools such a Claude Code or Opencode (`:CodeCompanionCLI`)
- **Inline** - An inline interaction that can write code directly into a buffer (`:CodeCompanion`)
- **Cmd** - Create Neovim commands in the command-line (`:CodeCompanionCmd`)
- **Background** - Runs tasks in the background such as compacting chat messages or generating titles for chats

## Setup

### Chat and Inline

> [!NOTE]
> The adapters that the plugin supports out of the box can be found in the
> [built-in adapters directory](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters). Or, see the
> [community-contributed adapters](configuration/adapters-http#community-adapters).
>
> [ACP adapters](/configuration/adapters-acp) are only supported for the chat interaction.

The Chat Buffer is where you can converse with an LLM from within a Neovim buffer. It operates on a single response per turn basis. The inline interaction enables an LLM to write code directly into a Neovim buffer.

The [chat](/usage/chat-buffer/) and [inline](/usage/inline) interactions need an adapter to function. In CodeCompanion terminology, an adapter is the connection between Neovim and an LLM or agent. CodeCompanion has two _types_ of adapters; HTTP adapters which connect you to an LLM via it's API and ACP adapters which connect you to an agent via the [Agent Client Protocol](https://agentclientprotocol.com). CodeCompanion has a number of [built-in adapters](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) that you can leverage and you can find more details in the respective [HTTP](/configuration/adapters-http) and [ACP](/configuration/adapters-acp) sections of the documentation.

To set an adapter:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      -- You can specify an adapter by name and model (both ACP and HTTP)
      adapter = {
        name = "copilot",
        model = "gpt-4.1",
      },
    },
    -- Or, just specify the adapter by name
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

In the example above, we're using the Copilot adapter for the chat interaction and the Anthropic one for the inline. We're also using something cheap for the background adapter (although these interactions are opt-in). You can mix and match adapters as you see fit for your workflow.

**Setting an API Key**

Because most LLMs require an API key, you'll need to share that with the adapter. By default, the built-in adapters will look in your environment for a `*_API_KEY` where `*` is the name of the adapter such as `ANTHROPIC` or `OPENAI`. Refer to the documentation of the LLM or agent you're using to find out what the environment variable is called.

You can set/change the API key by using the `extend` function:

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

### CLI

The CLI interaction allows you to interact with agents that operate in the command-line like Claude Code and Opencode. To use CodeCompanion with a CLI agent, you'll need to configure an agent first:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      agent = "claude_code",
      agents = {
        claude_code = {
          cmd = "claude",
          args = {},
          description = "Claude Code CLI",
          provider = "terminal",
        },
      },
    },
  },
})
```

In the example above, we're setting up Claude Code in the `agents` table, specifying the command to run it. Then we're setting it as the default CLI interaction with `agent = "claude_code"`.

## Usage

The below section has been curated from the lengthier usage documentation to give you a quick overview of how each feature works.

### Chat

<p align="center">
  <img src="https://github.com/user-attachments/assets/597299d2-36b3-469e-b69c-4d8fd14838f8" alt="Chat buffer">
</p>

Run `:CodeCompanionChat` to open a chat buffer. Type your prompt and send it by pressing `<C-s>` while in insert mode or `<CR>` in normal mode. Alternatively, run `:CodeCompanionChat why are Lua and Neovim so perfect together?` to open the chat buffer and send a prompt at the same time. Toggle the chat buffer with `:CodeCompanionChat Toggle`.

You can add context from your code base by using _Editor Context_ and _Slash Commands_ in the chat buffer.

**Editor Context**

_Editor Context_, accessed via `#` (by default), contain data about the present state of Neovim. You can find a [list of available editor context](/usage/chat-buffer/editor-context). The buffer editor context will automatically link a buffer to the chat buffer, by default, updating the LLM when the buffer changes.

You can use them in your prompts like:

```
What does the code in #{buffer} do?`
```

**Slash Commands**

> [!IMPORTANT]
> These have been designed to work with native Neovim completions alongside nvim-cmp and blink.cmp. To open the native completion menu use `<C-_>` in insert mode when in the chat buffer. Note: Slash commands should also work with coc.nvim.

_Slash commands_, accessed via `/` (by default), run commands to insert additional context into the chat buffer. You can find a [list of available slash commands and how to use them](/usage/chat-buffer/slash-commands).

**Tools**

_Tools_, accessed via `@` (by default), allow the LLM to function as an agent and leverage external tools. You can find a [list of available tools and how to use them](usage/chat-buffer/agents-tools#available-tools).

You can use them in your prompts like:

```
Can you use @{grep_search} to find occurrences of "hello world"
```

### CLI

<p align="center">
  <video controls title="CLI interaction demo" src="https://github.com/user-attachments/assets/9b4e202d-a939-4daa-8344-74af91f9f366"></video>
</p>

Running `:CodeCompanionCLI` will open a new CLI interaction. Running `:CodeCompanionCLI <your prompt>` will send the prompt to the last CLI interaction (or create a new one). You can also run `:CodeCompanionCLI Ask` to use a rich prompt input field complete with [editor context](#editor-context). Save with `:w` to send the prompt to the agent, or `:w!` to send and auto-submit it.

Adding `!` to the command (e.g. `:CodeCompanionCLI! <prompt>`) will auto-submit the prompt and keep your cursor in the current buffer. You can also specify which agent to use with `:CodeCompanionCLI agent=<agent name>`.

### Inline

<p align="center">
  <video controls muted title="Inline interaction demo" src="https://github.com/user-attachments/assets/11a42705-d9de-4eb5-a9ab-c8a2772fb4d4"></video>
</p>

> [!NOTE]
> The diff provider in the video is [mini.diff](https://github.com/echasnovski/mini.diff)

Run `:CodeCompanion your prompt` to call the inline interaction. The interaction will evaluate the prompt and either write code or open a chat buffer. You can also make a visual selection and call the inline interaction. To send additional context alongside your prompt, you can leverage [editor context](/usage/inline#editor-context) such as `:CodeCompanion #{buffer} <your prompt>`.

For convenience, you can call prompts with their `alias` from the [prompt library](https://github.com/olimorris/codecompanion.nvim/blob/6a4341a4cfe8988a57ad9e8b7dc01ccd6f3e1628/lua/codecompanion/config.lua#L565) such as `:'<,'>CodeCompanion /explain`. The prompt library comes with the following presets:

- `/commit` - Generate a commit message
- `/explain` - Explain how selected code in a buffer works
- `/fix` - Fix the selected code
- `/lsp` - Explain the LSP diagnostics for the selected code
- `/tests` - Generate unit tests for selected code

### Action Palette

<p align="center">
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" alt="Action Palette">
</p>

Run `:CodeCompanionActions` to open the action palette, which gives you access to the plugin's features, including your prompts from the [prompt library](/configuration/prompt-library).

By default the plugin uses `vim.ui.select`, however, you can change the provider by altering the `display.action_palette.provider` config value to be `telescope`, `mini_pick`  or `snacks`. You can also call the Telescope extension with `:Telescope codecompanion`.

> [!NOTE]
> Some actions and prompts will only be visible if you're in _Visual mode_.

### List of Commands

The plugin has five core commands:

- `CodeCompanion` - Open the inline interaction
- `CodeCompanionChat` - Open a chat buffer
- `CodeCompanionCLI` - Open a CLI interaction
- `CodeCompanionCmd` - Generate a command in the command-line
- `CodeCompanionActions` - Open the _Action Palette_

However, there are multiple options available:

- `CodeCompanion <prompt>` - Prompt the inline interaction
- `CodeCompanion adapter=<adapter> <prompt>` - Prompt the inline interaction with a specific adapter
- `CodeCompanion /<prompt library>` - Call an item via its alias from the [prompt library](configuration/prompt-library)
- `CodeCompanionChat <prompt>` - Send a prompt to the LLM via a chat buffer
- `CodeCompanionChat adapter=<adapter> model=<model>` - Open a chat buffer with a specific http adapter and model
- `CodeCompanionChat adapter=<adapter> command=<command>` - Open a chat buffer with a specific ACP adapter and command
- `CodeCompanionChat Add` - Add visually selected chat to the current chat buffer
- `CodeCompanionChat RefreshCache` - Used to refresh conditional elements in the chat buffer
- `CodeCompanionChat Toggle` - Toggle a chat buffer
- `CodeCompanionCLI` - Open a new CLI interaction
- `CodeCompanionCLI <prompt>` - Send a prompt to the last CLI interaction (or create a new one)
- `CodeCompanionCLI! <prompt>` - Send and auto-submit a prompt, keeping focus in the current buffer
- `CodeCompanionCLI agent=<agent> <prompt>` - Start a new CLI interaction with a specific agent
- `CodeCompanionCLI Ask` - Open the rich input buffer for CLI prompts

## Suggested Plugin Workflow

For an optimum plugin workflow, the author recommends the following:

```lua
vim.keymap.set({ "n", "v" }, "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<LocalLeader>a", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
vim.keymap.set("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
```

> [!NOTE]
> You can also assign prompts from the library to specific mappings. See the [prompt library](configuration/prompt-library#assigning-prompts-to-a-keymap) section for more information.
