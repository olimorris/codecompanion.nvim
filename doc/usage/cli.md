---
description: Learn how to use the Command-Line Interface (CLI) interaction to interact with CLI agents from within CodeCompanion.
---

# Using the Command-Line Interface (CLI)

The CLI interaction allows you to interact with agents that have a command-line interface such as [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) and [Codex](https://github.com/openai/codex).

## Commands

| Command | Behaviour |
|---|---|
| `:CodeCompanionCLI` | Open a new CLI interaction |
| `:CodeCompanionCLI <prompt>` | Send a prompt to the last CLI interaction (or create a new one) |
| `:CodeCompanionCLI! <prompt>` | Send a prompt and auto-submit it, keeping focus in the current buffer |
| `:CodeCompanionCLI agent=<name> <prompt>` | Start a new CLI interaction with a specific agent |
| `:CodeCompanionCLI Ask` | Open the rich input buffer for composing prompts |

### The Bang Modifier

Adding `!` to the command (e.g. `:CodeCompanionCLI! fix the tests`) will:

1. Send the prompt directly to the terminal process (auto-submit)
2. Keep your cursor in the current buffer instead of switching to the terminal

This is useful for "fire and forget" workflows where you want to send a prompt without leaving your current context.

### Rich Input Buffer

Running `:CodeCompanionCLI Ask` opens a compose buffer where you can write multi-line prompts and use [editor context](/usage/chat-buffer/editor-context) references (e.g. `#buffer`, `#selection`).

- `:w` — Send the prompt to the CLI agent (text is placed in the terminal but not submitted)
- `:w!` — Send and auto-submit the prompt

> [!NOTE]
> Editor context in CLI interactions reference paths to buffers rather than contents.

## Editor Context

You can share context from your editor using `#` references in your prompts, just like in the [chat buffer](/usage/chat-buffer/editor-context). For example:

````
#buffer what does this code do?
````

In the CLI interaction, editor context references resolve to file paths rather than file contents.
