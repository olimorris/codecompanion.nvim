---
description: "Look up every CodeCompanion command and the arguments each one takes."
---

# Commands

CodeCompanion has six commands: one for each interaction, plus the action palette and code reviews. None are mapped to keys by default.

## Chat

| Command | Description |
|---|---|
| `:CodeCompanionChat` | Open a new chat buffer |
| `:CodeCompanionChat <prompt>` | Open a chat buffer and send the prompt |
| `:CodeCompanionChat adapter=<adapter> model=<model>` | Open a chat buffer with a specific HTTP adapter and model |
| `:CodeCompanionChat adapter=<adapter> command=<command>` | Open a chat buffer with a specific ACP adapter and command |
| `:CodeCompanionChat Toggle` | Show or hide the last chat buffer, creating one if none exist |
| `:CodeCompanionChat Add` | Add the visual selection to the last chat buffer, creating one if none exist |
| `:CodeCompanionChat Changes` | Open every file the LLM has changed in the quickfix list |
| `:CodeCompanionChat RefreshCache` | Re-check which conditionally enabled tools and slash commands are available |

`adapter=` and `model=` can be used on their own, and alongside a prompt.

## Inline

| Command | Description |
|---|---|
| `:CodeCompanion` | Ask for a prompt, then send it to the inline interaction |
| `:CodeCompanion <prompt>` | Send the prompt to the inline interaction |
| `:CodeCompanion adapter=<adapter> <prompt>` | Send the prompt with a specific HTTP adapter |
| `:CodeCompanion /<alias> <prompt>` | Run a [prompt library](/usage/prompt-library) item by its alias, with an optional prompt of your own |

## CLI

| Command | Description |
|---|---|
| `:CodeCompanionCLI` | Open a new CLI interaction, or send the visual selection to the last one |
| `:CodeCompanionCLI <prompt>` | Send the prompt to the last CLI interaction, creating one if none exist |
| `:CodeCompanionCLI! <prompt>` | Send the prompt and submit it |
| `:CodeCompanionCLI agent=<agent>` | Open a new CLI interaction with a specific agent |
| `:CodeCompanionCLI agent=<agent> <prompt>` | Send the prompt to that agent's CLI interaction, creating one if none exist |
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
| `:CodeCompanionActions` | Open the [action palette](/usage/action-palette), or the chat's own palette from a chat buffer |
| `:CodeCompanionActions Refresh` | Reload the action palette and prompt library, then open it |
| `:CodeCompanionCmd <prompt>` | Generate a command for the command-line |
