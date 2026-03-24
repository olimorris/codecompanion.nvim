---
description: Learn how to use the Command-Line Interface (CLI) interaction to interact with CLI agents from within CodeCompanion.
---

# Using the Command-Line Interface (CLI)

<p align="center">
  <video controls src="https://github.com/user-attachments/assets/9b4e202d-a939-4daa-8344-74af91f9f366"></video>
</p>

The CLI interaction allows you to interact with agents that have a command-line interface such as [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) and [Codex](https://github.com/openai/codex).

_Why?_ Sharing context with an agent in the CLI can be cumbersome. You have to navigate to the CLI, press `@` search for the file or trigger a slash command. If you want to share a code snippet then that's a good ol' copy and paste job. With CodeCompanion, you can share context from Neovim in keystrokes, without leaving the buffer or the editor.

## Initiating a CLI Interaction

You can use `:CodeCompanionCLI` to start a new CLI interaction and CodeCompanion will leverage the agent you've configured in your config at `interactions.cli.agent`. If you want to specify an agent on the fly, you can use `:CodeCompanionCLI agent=<agent_name>`.

You can toggle a CLI interaction with `require("codecompanion").toggle()`, just as you would with a chat buffer. You can use `{` and `}` to cycle through all the chat and CLI interactions.

## Workflow

Below are some useful workflow tips to enable you to be productive when working with agents in the CLI with CodeCompanion:

### Prompting the Agent

You can send a custom prompt to the agent from within a Neovim buffer:

```lua
-- [C]odeCompanion [P]rompt]
vim.keymap.set({ "n", "v" }, "<LocalLeader>cp", function()
  return require("codecompanion").cli({ prompt = true })
end, { desc = "Prompt the CLI agent" })
```

In normal mode, this brings up the prompt input, allowing you to specify editor context before sending to the agent. In visual mode however, it shares the selection alongside your prompt, saving you from manually specifying editor context.

### Adding Context

You're working in a buffer and think _"I should share this with the agent"_ or _"This code is relevant to the conversation..."_:

```lua
-- [C]odeCompanion [A]dd
vim.keymap.set({ "n", "v" }, "<LocalLeader>ca", function()
  return require("codecompanion").cli("#{this}", { focus = false })
end, { desc = "Add context to the CLI agent" })
```

This keymap allows you to quickly share the current buffer or visual selection with the agent, without needing to specify a prompt, utilising `#{this}`. This is useful for quickly sharing context before following up with a more specific prompt. You'll also note the inclusion of `focus = false` to ensure that the cursor doesn't move into the CLI buffer.

This can be useful as you carefully move between buffers and code, determining what context is relevant to share with the agent, without losing your current position in the CLI buffer.

### Fixing LSP Diagnostics

If the LSP is throwing some warnings, share them with the agent in the CLI and ask it to fix them:

```lua
-- [C]odeCompanion [D]iagnostics
vim.keymap.set("n", "<LocalLeader>cd", function()
  return require("codecompanion").cli("#{diagnostics} Can you fix these?", { focus = false, submit = true })
end, { desc = "Send diagnostics to CLI agent" })
```

This keymap shares the LSP diagnostics for the current buffer with the agent, automatically submitting the prompt.

### Fixing Failing Tests

You've run your test suite in the terminal and observe some failures. Share them with the agent:

```lua
-- [C]odeCompanion [T]erminal
vim.keymap.set("n", "<LocalLeader>ct", function()
  return require("codecompanion").cli("#{terminal} Sharing the output from the terminal. Can you fix it?", { focus = false, submit = true })
end, { desc = "Send terminal output to CLI agent" })
```

This keymap shares the output from the most recent terminal with the agent, which is especially useful for sharing failing test output. Again, the prompt is automatically submitted to save you time.

## Sending Context

This section covers, more broadly, the ways that you can send context to an agent in the CLI. This should serve as inspiration for how you can leverage the CLI for your own workflow.

### Visual Selection

To start off, you can use a visual selection as a source of context, by visually selecting some code and running:

```
CodeCompanionCLI Can you explain this code?
```

You could also achieve this in Lua:

```lua
require("codecompanion").cli({ prompt = true })
```

This will result in the visual selection being passed to an input prompt, allowing you to type _"Can you explain this code?"_ before sending it to the agent.

Alternatively, you could hard code the prompt:

```lua
require("codecompanion").cli("Can you explain this code?")
```

### Editor Context

Similarly to the [chat buffer](/usage/chat-buffer/index), you can use [editor context](/usage/chat-buffer/editor-context) references in your prompts to share information about your current Neovim session. This makes it trivial to share the current buffer (`#{buffer}`), all currently open buffers (`#{buffers}`), or LSP diagnostics (`#{diagnostics}`) to name but a few.

You can use the `:CodeCompanionCLI` command:

```
CodeCompanionCLI Can you explain #{buffers}?
```

Which will be expanded in the agent CLI to be:

```log
❯ Can you explain the open buffers:
  @your_file_path
  @your_other_file_path?
```

Alternatively:

```lua
require("codecompanion").cli("Can you explain #{buffers}?")
```

---

CodeCompanion also provides `#{this}` (unique to the CLI interaction) which resolves to the current buffer in normal mode, and the visual selection in visual mode:

```
CodeCompanionCLI What does #{this} do?
```

In normal mode, this will resolve to be:

```log
❯ What does @your_file_path do?
```

and with a visual selection, will resolve to be:

`````log
❯ What does the selected code in @your_file_path do?

  - Selected code from @your_file_path (lines 3-4):
  ````lua
  local new_set = MiniTest.new_set
  local T = new_set()
  ````
`````

> [!NOTE]
> `@path` references are understood natively by CLI agents like Claude Code and Codex, allowing them to read files directly.

### Prompts

There will come a time when you need to send a more complex prompt to the agent. Whilst you can do `:CodeCompanionCLI <my long prompt>`, you can also bring up a prompt input with:

```
CodeCompanionCLI Ask
```

or:

```lua
require("codecompanion").cli({ prompt = true })
```

This will toggle a `codecompanion_input` buffer. In this buffer, you have access to all of the available [editor context](#editor-context), some [slash commands](#slash-commands) and a much a larger character window. To send the prompt to the agent, you can write the buffer with `:w`. Or, to automatically send and submit, you can forcefully write with `:w!`.

You can scroll previous prompts with the `<up>` and `<down>` keys.

### Slash Commands

The prompt input buffer also supports the [buffer](/usage/chat-buffer/slash-commands#buffer]) and [file](/usage/chat-buffer/slash-commands#file) slash commands, which better enable you to share lots of context with a CLI agent at once. Simply type `/` in the buffer to bring up the completion menu for your selected provider.

Instead of sharing file contents, CLI slash commands insert `@path` references into the prompt. For example, selecting a file via `/file` will insert:

```markdown
@./lua/codecompanion/init.lua
```

If you select multiple files, each one is added on its own line:

```markdown
@./lua/codecompanion/init.lua
@./lua/codecompanion/config.lua
```

### Auto-Submit

By default, prompts are sent to the agent but _not_ submitted. The text appears in the CLI and you can review it before pressing enter. To automatically submit a prompt so the agent starts working immediately, you can:

Use the _bang_ form of the command:

```
CodeCompanionCLI! #{diagnostics} Can you fix these?
```

Or pass `submit = true` in Lua:

```lua
require("codecompanion").cli("#{diagnostics} Can you fix these?", { submit = true })
```

This is especially useful in keymaps where you want a fire-and-forget workflow, like the diagnostics and terminal examples in the [Workflow](#workflow) section.

## API Reference

The `require("codecompanion").cli()` function is the main entry point for interacting with CLI agents. It has a polymorphic signature:

```lua
-- No args: create a new CLI instance and open it
require("codecompanion").cli()

-- Opts table: create a new instance with options
require("codecompanion").cli({ agent = "claude_code" })

-- String prompt: send to the last instance (or create one)
require("codecompanion").cli("Can you explain this code?")

-- String prompt with opts
require("codecompanion").cli("Fix #{diagnostics}", { submit = true, focus = false })
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `agent` | `string` | config default | The CLI agent to use. When sending a prompt, reuses an existing instance of this agent if one exists |
| `focus` | `boolean` | `true` | Whether to open the CLI window and move the cursor to it. Set to `false` to send context in the background |
| `submit` | `boolean` | `false` | Automatically submit the prompt (press enter) so the agent starts working immediately |
| `prompt` | `boolean` | `false` | Open the prompt input buffer instead of sending directly. If a string prompt is also provided, it pre-fills the input |
| `width` | `number` | config default | Override the CLI window width |
| `height` | `number` | config default | Override the CLI window height |
