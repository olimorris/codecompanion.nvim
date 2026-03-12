---
description: Learn how to use the Command-Line Interface (CLI) interaction to interact with CLI agents from within CodeCompanion.
---

# Using the Command-Line Interface (CLI)

The CLI interaction allows you to interact with agents that have a command-line interface such as [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) and [Codex](https://github.com/openai/codex).

You can toggle a CLI buffer with `require("codecompanion").toggle()` and you can use `{` and `}` to cycle through chat and CLI interactions.

## Commands

There are many ways to start a CLI interaction, depending on your workflow:


| Command | Behaviour |
|---|---|
| `:CodeCompanionCLI` | Open a new CLI interaction |
| `:CodeCompanionCLI <prompt>` | Send a prompt to the last CLI interaction (or create a new one) |
| `:CodeCompanionCLI! <prompt>` | Send a prompt and auto-submit it, keeping focus in the current buffer |
| `:CodeCompanionCLI agent=<name> <prompt>` | Start a new CLI interaction with a specific agent |
| `:CodeCompanionCLI Ask` | Open the rich input buffer for composing prompts (case-sensitive) |


### The Bang Modifier

Adding `!` to the command (e.g. `:CodeCompanionCLI! fix the tests`) will:

1. Send the prompt directly to the terminal process (auto-submit)
2. Keep your cursor in the current buffer instead of switching to the terminal

This is useful for "fire and forget" workflows where you want to send a prompt without leaving your current context.

### Rich Input Buffer

Running `:CodeCompanionCLI Ask` opens an input buffer where you can write multi-line prompts and use [editor context](/usage/chat-buffer/editor-context) references (e.g. `#{buffer}`, `#{this}`).

- `:w` — Sends the prompt to the CLI agent
- `:w!` — Sends and auto-submits the prompt

> [!NOTE]
> Editor context in CLI interactions reference paths to buffers rather than contents.

## Editor Context

You can share context from your editor using `#` references in your prompts, just like in the [chat buffer](/usage/chat-buffer/editor-context). For example:

````
What does this #{buffer} do?
````

Will be expanded to:

````
What does <file path="your_file_path"> do?
````

### #this

The `#{this}` editor context is a smart shortcut that adapts based on your current mode:

- **Normal mode** — resolves to the current buffer (like `#{buffer}`)
- **Visual mode** — resolves to the visual selection (like `#{selection}`)

````
:'<,'>CodeCompanionCLI #{this} what does this code do?
````

## Lua API

You can also interact with the CLI, programmatically:

```lua
-- Open a new CLI interaction (no prompt)
require("codecompanion").ask_cli()

-- Send a prompt to the last CLI interaction (or create a new one)
require("codecompanion").ask_cli("fix the failing tests")

-- Send and auto-submit a prompt, keeping focus in the current buffer
require("codecompanion").ask_cli("fix the failing tests", { submit = true })

-- Use a specific agent
require("codecompanion").ask_cli("hello", { agent = "codex" })

-- Toggle the CLI terminal buffer
require("codecompanion").toggle_cli()
```
