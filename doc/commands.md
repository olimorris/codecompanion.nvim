---
description: "Every CodeCompanion command in Neovim and the arguments each one takes."
---

# Commands

CodeCompanion has six commands, one per interaction plus the action palette and code review. None of them are mapped to keys by default.

## Chat

| Command | Description |
|---|---|
| `:CodeCompanionChat` | Open a new chat buffer |
| `:CodeCompanionChat <prompt>` | Open a chat buffer and send the prompt |
| `:CodeCompanionChat adapter=<adapter> model=<model>` | Open a chat buffer with a specific HTTP adapter and model |
| `:CodeCompanionChat adapter=<adapter> command=<command>` | Open a chat buffer with a specific ACP adapter and command |
| `:CodeCompanionChat Toggle` | Show or hide the last chat buffer, creating one if none exist |
| `:CodeCompanionChat Add` | Add the visual selection to the current chat buffer |
| `:CodeCompanionChat Changes` | Open every file the LLM has changed in the quickfix list |
| `:CodeCompanionChat RefreshCache` | Refresh the editor context, slash commands and tools that are conditionally enabled |

## Inline

| Command | Description |
|---|---|
| `:CodeCompanion <prompt>` | Send the prompt to the inline interaction |
| `:CodeCompanion adapter=<adapter> <prompt>` | Send the prompt with a specific adapter |
| `:CodeCompanion /<alias>` | Run a [prompt library](/usage/prompt-library) item by its alias |

## CLI

| Command | Description |
|---|---|
| `:CodeCompanionCLI` | Open a new CLI interaction |
| `:CodeCompanionCLI <prompt>` | Send the prompt to the last CLI interaction, creating one if none exist |
| `:CodeCompanionCLI! <prompt>` | Send and submit the prompt, keeping the cursor in the current buffer |
| `:CodeCompanionCLI agent=<agent> <prompt>` | Start a new CLI interaction with a specific agent |
| `:CodeCompanionCLI Ask` | Write the prompt in a buffer with editor context, then save to send it |
| `:CodeCompanionCLI Install` | Write CodeCompanion's hooks into your CLI agents' settings |

## Code Review

| Command | Description |
|---|---|
| `:CodeCompanionCodeReview` | Open the changes made since the last review in the [review window](/usage/code-review) |
| `:CodeCompanionCodeReview Branch` | Review every change on the branch since it left the default branch |
| `:CodeCompanionCodeReview Comment` | Comment on the current line or visual selection |

## Others

| Command | Description |
|---|---|
| `:CodeCompanionActions` | Open the [action palette](/usage/action-palette) |
| `:CodeCompanionActions Refresh` | Reload the action palette and prompt library |
| `:CodeCompanionCmd <prompt>` | Generate a command in the command-line |
