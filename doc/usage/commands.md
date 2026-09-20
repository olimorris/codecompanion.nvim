---
description: "Every CodeCompanion.nvim command in Neovim, from the five core commands through to the adapter, prompt library and code review variants."
---

# Commands

The plugin has five core commands:

- `CodeCompanion` - Open the inline interaction
- `CodeCompanionChat` - Open a chat buffer
- `CodeCompanionCLI` - Open a CLI interaction
- `CodeCompanionCLI Install` - Write CodeCompanion's hooks into your CLI agents' settings
- `CodeCompanionCmd` - Generate a command in the command-line
- `CodeCompanionActions` - Open the _Action Palette_

However, there are multiple options available:

- `CodeCompanion <prompt>` - Prompt the inline interaction
- `CodeCompanion adapter=<adapter> <prompt>` - Prompt the inline interaction with a specific adapter
- `CodeCompanion /<prompt library>` - Call an item via its alias from the [prompt library](/configuration/prompt-library)
- `CodeCompanionActions Refresh` - Refresh the action palette and any items in the prompt library
- `CodeCompanionChat <prompt>` - Send a prompt to the LLM via a chat buffer
- `CodeCompanionChat adapter=<adapter> model=<model>` - Open a chat buffer with a specific http adapter and model
- `CodeCompanionChat adapter=<adapter> command=<command>` - Open a chat buffer with a specific ACP adapter and command
- `CodeCompanionChat Add` - Add visually selected chat to the current chat buffer
- `CodeCompanionChat Changes` - Open the quickfix list with all files that have been changed by the LLM
- `CodeCompanionChat RefreshCache` - Used to refresh conditional elements in the chat buffer
- `CodeCompanionChat Toggle` - Toggle a chat buffer
- `CodeCompanionCLI` - Open a new CLI interaction
- `CodeCompanionCLI <prompt>` - Send a prompt to the last CLI interaction (or create a new one)
- `CodeCompanionCLI! <prompt>` - Send and auto-submit a prompt, keeping focus in the current buffer
- `CodeCompanionCLI agent=<agent> <prompt>` - Start a new CLI interaction with a specific agent
- `CodeCompanionCLI Ask` - Open the rich input buffer for CLI prompts
- `CodeCompanionCodeReview` - Open an agent's changes in the quickfix list for [code reviews](/usage/code-review)
- `CodeCompanionCodeReview Comment` - Leave a review comment on the current line or visual selection
