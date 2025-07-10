# Getting Started

Please see the author's own [config](https://github.com/olimorris/dotfiles/blob/main/.config/nvim/lua/plugins/coding.lua) for a complete reference of how to setup the plugin.

> [!IMPORTANT]
> The default adapter in CodeCompanion is [GitHub Copilot](https://docs.github.com/en/copilot/using-github-copilot/copilot-chat/asking-github-copilot-questions-in-your-ide). If you have [copilot.vim](https://github.com/github/copilot.vim) or [copilot.lua](https://github.com/zbirenbaum/copilot.lua) installed then expect CodeCompanion to work out of the box.

## Configuring an Adapter

> [!NOTE]
> The adapters that the plugin supports out of the box can be found [here](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters). Or, see the user contributed adapters [here](configuration/adapters.html#community-adapters)

An adapter is what connects Neovim to an LLM. It's the interface that allows data to be sent, received and processed. In order to use the plugin, you need to make sure you've configured an adapter first:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic",
    },
    inline = {
      adapter = "anthropic",
    },
  },
}),
```

In the example above, we're using the Anthropic adapter for both the chat and inline strategies. Refer to the [adapter](configuration/adapters#changing-a-model) section to understand how to change the default model.

Because most LLMs require an API key you'll need to share that with the adapter. By default, adapters will look in your environment for a `*_API_KEY` where `*` is the name of the adapter such as `ANTHROPIC` or `OPENAI`. However, you can extend the adapter and change the API key like so:

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = function()
      return require("codecompanion.adapters").extend("anthropic", {
        env = {
          api_key = "MY_OTHER_ANTHROPIC_KEY"
        },
      })
    end,
  },
}),
```

Having API keys in plain text in your shell is not always safe. Thanks to [this PR](https://github.com/olimorris/codecompanion.nvim/pull/24), you can run commands from within your config by prefixing them with `cmd:`. In the example below, we're using the 1Password CLI to read an OpenAI credential.

```lua
require("codecompanion").setup({
  adapters = {
    openai = function()
      return require("codecompanion.adapters").extend("openai", {
        env = {
          api_key = "cmd:op read op://personal/OpenAI/credential --no-newline",
        },
      })
    end,
  },
}),
```

> [!IMPORTANT]
> Please see the section on [Configuring Adapters](configuration/adapters) for more information

## Chat Buffer

<p align="center">
  <img src="https://github.com/user-attachments/assets/597299d2-36b3-469e-b69c-4d8fd14838f8" alt="Chat buffer">
</p>

The Chat Buffer is where you can converse with an LLM from within Neovim. It operates on a single response per turn, basis.

Run `:CodeCompanionChat` to open a chat buffer. Type your prompt and send it by pressing `<C-s>` while in insert mode or `<CR>` in normal mode. Alternatively, run `:CodeCompanionChat why are Lua and Neovim so perfect together?` to open the chat buffer and send a prompt at the same time. Toggle the chat buffer with `:CodeCompanionChat Toggle`.

You can add context from your code base by using _Variables_ and _Slash Commands_ in the chat buffer.

> [!IMPORTANT]
> As of `v17.5.0`, variables and tools are now wrapped in curly braces, such as `#{buffer}` or `@{files}`

### Variables

_Variables_, accessed via `#`, contain data about the present state of Neovim:

- `buffer` - Shares the current buffer's code. This can also receive [parameters](usage/chat-buffer/variables#buffer)
- `lsp` - Shares LSP information and code for the current buffer
- `viewport` - Shares the buffers and lines that you see in the Neovim viewport

> [!TIP]
> Use them in your prompt like: `What does the code in #{buffer} do?`, ensuring they're wrapped in curly brackets

### Slash Commands

> [!IMPORTANT]
> These have been designed to work with native Neovim completions alongside nvim-cmp and blink.cmp. To open the native completion menu use `<C-_>` in insert mode when in the chat buffer. Note: Slash commands should also work with coc.nvim.

_Slash commands_, accessed via `/`, run commands to insert additional context into the chat buffer:

- `/buffer` - Insert open buffers
- `/fetch` - Insert URL contents
- `/file` - Insert a file
- `/quickfix` - Insert entries from the quickfix list
- `/help` - Insert content from help tags
- `/now` - Insert the current date and time
- `/symbols` - Insert symbols from a selected file
- `/terminal` - Insert terminal output

### Agents / Tools

_Tools_, accessed via `@`, allow the LLM to function as an agent and carry out actions:

- `cmd_runner` - The LLM will run shell commands (subject to approval)
- `create_file` - The LLM will create a file in the current working directory (subject to approval)
- `file_search` - The LLM can search for a file in the CWD
- `get_changed_files` - The LLM can get git diffs for any changed files in the CWD
- `grep_search` - The LLM can search within files in the CWD
- `insert_edit_into_file` - The LLM will edit code in a Neovim buffer or on the file system (subject to approval)
- `next_edit_suggestion` - The LLM can show the user where the next edit is
- `read_file` - The LLM can read a specific file
- `web_search` -  The LLM can search the internet for information

Tools can also be grouped together, also accessible via `@` in the chat buffer:

- `files` - Contains the `create_file`, `file_search`, `get_changed_files`, `grep_search`, `insert_edit_into_file` and `read_file` tools

> [!TIP]
> Use them in your prompt like: `Can you use the @{grep_search} tool to find occurrences of "add_message"`, ensuring they're wrapped in curly brackets

## Inline Assistant

<p align="center">
  <video controls muted src="https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee"></video>
</p>

> [!NOTE]
> The diff provider in the video is [mini.diff](https://github.com/echasnovski/mini.diff)

The inline assistant enables an LLM to write code directly into a Neovim buffer.

Run `:CodeCompanion <your prompt>` to call the inline assistant. The assistant will evaluate the prompt and either write code or open a chat buffer. You can also make a visual selection and call the assistant. To send additional context alongside your prompt, you can leverage [variables](/usage/inline-assistant#variables) such as `:CodeCompanion #{buffer} <your prompt>`:

- `buffer` - shares the contents of the current buffer
- `chat` - shares the LLM's messages from the last chat buffer

For convenience, you can call prompts from the [prompt library](/configuration/prompt-library) via the cmd line, such as `:'<,'>CodeCompanion /explain`. The prompt library comes with the following defaults:

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
- `CodeCompanion <adapter> <prompt>` - Prompt the inline assistant with a specific adapter
- `CodeCompanion /<prompt library>` - Call an item from the [prompt library](configuration/prompt-library)
- `CodeCompanionChat <prompt>` - Send a prompt to the LLM via a chat buffer
- `CodeCompanionChat <adapter>` - Open a chat buffer with a specific adapter
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
