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
| `:CodeCompanionCLI Ask` | Open the prompt input buffer for composing prompts (case-sensitive) |


### The Bang Modifier

Adding `!` to the command (e.g. `:CodeCompanionCLI! fix the tests`) will:

1. Send the prompt directly to the terminal process (auto-submit)
2. Keep your cursor in the current buffer instead of switching to the terminal

This is useful for "fire and forget" workflows where you want to send a prompt without leaving your current context.

### Prompt Input Buffer

Running `:CodeCompanionCLI Ask` opens a prompt input buffer where you can write multi-line prompts and use [editor context](/usage/chat-buffer/editor-context) references (e.g. `#{buffer}`, `#{this}`).

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

### Visual Selection

When you make a visual selection, the selected code is automatically included with your prompt:

````
:'<,'>CodeCompanionCLI what does this code do?
````

This also works with the Lua API when called from a visual mode keymap:

```lua
vim.keymap.set("v", "<LocalLeader>ca", function()
  require("codecompanion").cli("what does this code do?")
end)
```

## Lua API

The `cli()` function is the main entry point for interacting with CLI agents programmatically:

```lua
---Open, send to, or interact with a CLI agent
---@param prompt_or_opts? string|table A prompt string, or an opts table when no prompt is needed
---@param opts? table Options (see below)
require("codecompanion").cli(prompt_or_opts, opts)
```

### Parameters

The first argument to the `cli` function is polymorphic. It can be a prompt string or an options table:

- `cli()` — create and open a new CLI instance with the default agent
- `cli("prompt")` — send a prompt to the last instance (or create one)
- `cli("prompt", opts)` — send a prompt with options
- `cli(opts)` — create a new instance with the given options (no prompt)

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `agent` | `string` | config default | Which agent to use. When sending a prompt, reuses an existing instance of that agent if one exists |
| `submit` | `boolean` | `false` | Auto-submit the prompt (sends `Enter` after the text) |
| `focus` | `boolean` | `true` | Open the CLI window and move the cursor to it. When `false`, the prompt is sent in the background |
| `prompt` | `boolean` | `false` | Open the prompt input buffer for composing multi-line prompts |
| `width` | `number` | — | Override the window width (fraction of editor, e.g. `0.5`) |
| `height` | `number` | — | Override the window height (fraction of editor, e.g. `0.8`) |

### Examples

```lua
-- Open a new CLI interaction
require("codecompanion").cli()

-- Open a new CLI interaction with a specific agent
require("codecompanion").cli({ agent = "codex" })

-- Send a prompt to the last CLI interaction (or create one)
require("codecompanion").cli("fix the failing tests")

-- Send and auto-submit a prompt
require("codecompanion").cli("fix the failing tests", { submit = true })

-- Send a prompt without opening or focusing the CLI
require("codecompanion").cli("explain #{buffer}", { focus = false })

-- Fire-and-forget: submit to a specific agent, stay in current buffer
require("codecompanion").cli("run the test suite", { agent = "claude_code", submit = true, focus = false })

-- Open the prompt input buffer for composing a multi-line prompt
require("codecompanion").cli({ prompt = true })

-- Override window dimensions
require("codecompanion").cli("fix the tests", { width = 0.5, height = 0.8 })
```

### Keymap Examples

```lua
-- Toggle the CLI (show/hide)
vim.keymap.set("n", "<Leader>ct", function()
  require("codecompanion").toggle()
end)

-- Quick send: buffer (normal mode) or selection (visual mode) straight to the CLI
vim.keymap.set({ "n", "v" }, "<Leader>ca", function()
  require("codecompanion").cli("#{this}")
end)

-- Compose: open the prompt input buffer to write a multi-line prompt
vim.keymap.set({ "n", "v" }, "<Leader>cp", function()
  require("codecompanion").cli({ prompt = true })
end)
```

### Other Functions

```lua
-- Toggle the CLI terminal buffer (show/hide)
require("codecompanion").toggle_cli()

-- Toggle the last used interaction (chat or CLI)
require("codecompanion").toggle()
```
