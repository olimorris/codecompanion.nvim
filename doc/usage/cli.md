---
description: "Share context and send prompts from Neovim to CLI agents like Claude Code and Codex."
---

# Using the CLI

<p align="center">
  <video controls title="CLI interaction demo" src="https://github.com/user-attachments/assets/9b4e202d-a939-4daa-8344-74af91f9f366"></video>
</p>

The _CLI interaction_ runs agents with a command-line interface, such as [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) and [Codex](https://github.com/openai/codex), in a Neovim terminal.

Sharing context with an agent in a terminal is slow: switch to it, type `@`, search for the file, or copy and paste a snippet. CodeCompanion sends context from the buffer you're in, in a few keystrokes.

## Starting an Agent

Agents are defined in your config. See [Configuring the CLI](/configuration/cli#agents) to add one.

To start the agent set at `interactions.cli.agent`:

```
:CodeCompanionCLI
```

To start a different one:

```
:CodeCompanionCLI agent=codex
```

`require("codecompanion").toggle()` shows or hides it, as it does a chat buffer, and `{` and `}` cycle through every chat and CLI agent.

## Workflow

These keymaps cover the most common ways of working with an agent.

### Prompting the Agent

To write a prompt from any buffer:

```lua
vim.keymap.set({ "n", "v" }, "<LocalLeader>cp", function()
  return require("codecompanion").cli({ prompt = true })
end, { desc = "Prompt the CLI agent" })
```

In normal mode, this opens the [prompt input](#prompts). In visual mode, the selection is sent along with your prompt.

### Adding Context

To share the current buffer, or the visual selection, without writing a prompt:

```lua
vim.keymap.set({ "n", "v" }, "<LocalLeader>ca", function()
  return require("codecompanion").cli("#{this}", { focus = false })
end, { desc = "Add context to the CLI agent" })
```

`focus = false` keeps your cursor where it is, so you can move through your code adding context before you write the prompt.

### Fixing LSP Diagnostics

To send the current buffer's diagnostics and ask the agent to fix them:

```lua
vim.keymap.set("n", "<LocalLeader>cd", function()
  return require("codecompanion").cli("#{diagnostics} Can you fix these?", { focus = false, submit = true })
end, { desc = "Send diagnostics to CLI agent" })
```

### Fixing Failing Tests

To send the output of the most recent terminal, such as a failing test run:

```lua
vim.keymap.set("n", "<LocalLeader>ct", function()
  return require("codecompanion").cli("#{terminal} Sharing the output from the terminal. Can you fix it?", { focus = false, submit = true })
end, { desc = "Send terminal output to CLI agent" })
```

## Sending Context

### Visual Selection

Select some code, then:

```
:CodeCompanionCLI Can you explain this code?
```

Or with Lua:

```lua
require("codecompanion").cli("Can you explain this code?")
```

### Editor Context

[Editor context](/usage/chat-buffer/editor-context) works as it does in the chat buffer, such as `#{buffer}`, `#{buffers}` and `#{diagnostics}`:

```
:CodeCompanionCLI Can you explain #{buffers}?
```

The agent receives:

```log
❯ Can you explain the open buffers:
  @your_file_path
  @your_other_file_path?
```

`#{this}` is only available in the CLI interaction. It's the current buffer in normal mode and the selection in visual mode:

```
:CodeCompanionCLI What does #{this} do?
```

In normal mode, the agent receives:

```log
❯ What does @your_file_path do?
```

With a visual selection:

`````log
❯ What does the selected code in @your_file_path do?

  - Selected code from @your_file_path (lines 3-4):
  ````lua
  local new_set = MiniTest.new_set
  local T = new_set()
  ````
`````

> [!NOTE]
> Agents such as Claude Code and Codex read `@path` references as files

### Prompts

For a longer prompt, open the _prompt input_:

```
:CodeCompanionCLI Ask
```

Or with Lua:

```lua
require("codecompanion").cli({ prompt = true })
```

The prompt input is a `codecompanion_input` buffer with [editor context](#editor-context) and [slash commands](#slash-commands). Write it with `:w` to send the prompt, or `:w!` to send and submit it. Press `<Up>` and `<Down>` to scroll through earlier prompts.

### Slash Commands

The prompt input supports the [/buffer](/usage/chat-buffer/slash-commands#buffer) and [/file](/usage/chat-buffer/slash-commands#file) slash commands. Type `/` to open the completion menu.

Rather than sharing a file's contents, they insert an `@path` reference, one per line:

```markdown
@./lua/codecompanion/init.lua
@./lua/codecompanion/config.lua
```

### Auto-Submit

By default, a prompt is typed into the agent but not submitted, so you can review it before pressing enter. To submit it straight away, use the bang form of the command:

```
:CodeCompanionCLI! #{diagnostics} Can you fix these?
```

Or pass `submit = true`:

```lua
require("codecompanion").cli("#{diagnostics} Can you fix these?", { submit = true })
```

## API Reference

`require("codecompanion").cli()` takes a prompt, an options table or both:

```lua
-- Start a new agent
require("codecompanion").cli()

-- Start a new agent with options
require("codecompanion").cli({ agent = "claude_code" })

-- Send a prompt to the last agent, starting one if needed
require("codecompanion").cli("Can you explain this code?")

-- Send a prompt with options
require("codecompanion").cli("Fix #{diagnostics}", { submit = true, focus = false })
```

### Options

| Option | Default | Description |
| --- | --- | --- |
| `agent` | `interactions.cli.agent` | The agent to use. A prompt goes to a running instance of it, if there is one |
| `focus` | `true` | Open the agent's window and move the cursor to it |
| `submit` | `false` | Submit the prompt so the agent starts working |
| `prompt` | `false` | Open the prompt input, filled with the prompt if one is given |
| `width` | From your config | The window's width |
| `height` | From your config | The window's height |
