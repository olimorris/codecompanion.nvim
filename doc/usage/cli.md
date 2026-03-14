---
description: Learn how to use the Command-Line Interface (CLI) interaction to interact with CLI agents from within CodeCompanion.
---

# Using the Command-Line Interface (CLI)

The CLI interaction allows you to interact with agents that have a command-line interface such as [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) and [Codex](https://github.com/openai/codex).

You can toggle a CLI interaction with `require("codecompanion").toggle()`, just as you would with a chat buffer. You can use `{` and `}` to cycle through all the chat and CLI interactions.

## Initiating a CLI Interaction

You can use `:CodeCompanionCLI` to start a new CLI interaction and CodeCompanion will leverage the agent you've configured in your config at `interactions.cli.agent`. If you want to specify an agent on the fly, you can use `:CodeCompanionCLI agent=<agent_name>`.

## Sending Context

One of the key advantages of using an agent with CodeCompanion is the ability to share context from Neovim quickly. This section will cover the many different ways you can achieve this.

### Visual Selection

To start off, you can use a visual selection as a source of context, by visually selecting some code and running:

```
CodeCompanionCLI Can you explain this code?
```

You could also achieve this via a keymap:

```lua
vim.keymap.set("v", "<LocalLeader>cp", function()
  return require("codecompanion").cli({ prompt = true })
end)
```

This will result in the visual selection being passed to an input prompt, allowing you to type _"Can you explain this code?"_ before sending it to the agent.

Alternatively, you could hard code the prompt in the keymap:

```lua
vim.keymap.set("v", "<LocalLeader>cx", function()
  return require("codecompanion").cli("Can you explain this code?")
end)
```

### Editor Context

Similarly to the [chat buffer](/usage/chat-buffer), you can use [editor context](/usage/chat-buffer/editor-context) references in your prompts to share information about your current Neovim session. This makes it trivial to share the current buffer (`#{buffer}`), all currently open buffers (`#{buffers}`), or LSP diagnostics (`#{diagnostics}`) to name but a few.

You can use the `:CodeCompanionCLI` command:

```
CodeCompanionCLI What does this #{buffer} do?
```

Which will be expanded in the agent CLI to be:

```log
❯ What does `your_file_path` do?

  - Sharing file at path `your_file_path`
```

Alternatively, you can use the `require("codecompanion").cli()` function:

```lua
require("codecompanion").cli("What does #{buffer} do?")
```

---

CodeCompanion also provides `#{this}` (unique to the CLI interaction) which resolves to the current buffer in normal mode, and the visual selection in visual mode:

```
CodeCompanionCLI What does #{this} do?
```

In normal mode, this will resolve to be:

```log
❯ What does `your_file_path` do?

  - Sharing file at path `your_file_path`
```

and with a visual selection, will resolve to be:

`````log
❯ What does the selected code in `your_file_path` do?

  - Selected code from `your_file_path` (lines 3-4):
  ````lua
  local new_set = MiniTest.new_set
  local T = new_set()
  ````
`````


### Prompts

There will come a time when you need to send a more complex prompt to the agent. Whilst you can do `:CodeCompanionCLI <my long prompt>`, you can also bring up a prompt input with:

```
CodeCompanionCLI Ask
```

This will open up a `codecompanion_input` buffer. This gives you access to all of the available editor context and a much a larger character window. To send the prompt to the agent, you can write the buffer with `:w`. Or, to automatically send and submit, you can forcefully write with `:w!`.

## Useful Keymaps

So, with all of the above in mind, what are some useful keymaps to enable you to be as productive as possible when working with agents in the CLI with CodeCompanion? Below are some examples:

### Prompt the Agent

```lua
-- [C]odeCompanion [P]rompt]
vim.keymap.set({ "n", "v" }, "<LocalLeader>cp", function()
  return require("codecompanion").cli({ prompt = true })
end, { desc = "Prompt the CLI agent" })
```

In normal mode, this brings up the prompt input, allowing you to specify editor context before sending to the agent. In visual mode however, it shares the selection alongside your prompt, saving you from manually specifying editor context.

### Add Context

```lua
-- [C]odeCompanion [A]dd
vim.keymap.set({ "n", "v" }, "<LocalLeader>ca", function()
  return require("codecompanion").cli("#{this}", { focus = false })
end, { desc = "Add context to the CLI agent" })
```

This keymap allows you to quickly share the current buffer or visual selection with the agent, without needing to specify a prompt, utilising `#{this}`. This is useful for quickly sharing context before following up with a more specific prompt. You'll also note the inclusion of `focus = false` to ensure that the cursor doesn't move into the CLI buffer.

This can be useful as you carefully move between buffers and code, determining what context is relevant to share with the agent, without losing your current position in the CLI buffer.

### Fix LSP Diagnostics

```lua
-- [C]odeCompanion [D]iagnostics
vim.keymap.set("n", "<LocalLeader>cd", function()
  return require("codecompanion").cli("#{diagnostics} Can you fix these?", { focus = false, submit = true })
end, { desc = "Send diagnostics to CLI agent" })
```

This keymap shares the LSP diagnostics for the current buffer with the agent, automatically submitting the prompt.

### Fix Failing Tests

```lua
-- [C]odeCompanion [T]erminal
vim.keymap.set("n", "<LocalLeader>ct", function()
  return require("codecompanion").cli("#{terminal} Sharing the output from the terminal. Can you fix it?", { focus = false, submit = true })
end, { desc = "Send terminal output to CLI agent" })
```

This keymap shares the output from the most recent terminal with the agent, which is especially useful for sharing failing test output. Again, the prompt is automatically submitted to save you time.
