---
description: "Connect CodeCompanion to other applications, including herdr and Rex, which show whether CodeCompanion is idle, working or blocked."
---

# Integrations

CodeCompanion fires [events](/usage/events) as it works, so other applications can follow what it's doing. Some integrations are built in.

## herdr

<p align="center">
<video controls muted title="Integration with herdr" src="https://github.com/user-attachments/assets/f58738a2-c0ff-4a3f-9ffa-c8a51efd23be"></video>
</p>

[herdr](https://github.com/herdrdev/herdr) supervises terminal panes and shows which agent is running in each one. When Neovim runs in a herdr pane, CodeCompanion [reports its state](https://herdr.dev/docs/integrations/#integrate-your-own-agent) to herdr, so the pane sits alongside panes running Claude Code or Codex:

| State | Description |
|---|---|
| `working` | A chat buffer or CLI interaction is waiting on a response, compacting or running tools |
| `blocked` | A tool approval or a question from the LLM is waiting on you |
| `idle` | Nothing is in progress |

Every chat buffer and CLI interaction in the Neovim instance counts towards the pane's state, and a `blocked` interaction takes priority.

The integration is enabled by default, and does nothing outside of herdr. To disable it:

```lua
require("codecompanion").setup({
  integrations = {
    herdr = {
      enabled = false,
    },
  },
})
```

## Rex

[Rex](https://www.superlogical.com/rex) is a terminal multiplexer that shows what the programs in its panes are doing. When Neovim runs in Rex, CodeCompanion reports each chat buffer and CLI interaction with the [Program Status Protocol](https://www.superlogical.com/rex/docs/build/program-status), so they appear in Rex's tabs, session picker and activity view:

| State | Description |
|---|---|
| `working` | Waiting on a response, compacting or running tools |
| `blocked` | A tool approval or a question from the LLM is waiting on you |
| `done` | Finished a response you haven't looked at yet |
| `idle` | Open, with nothing in progress |

Each chat buffer and CLI interaction is reported separately, under its title where it has one. Closing it removes it from Rex, as does quitting Neovim.

The integration is enabled by default, and does nothing outside of Rex. To disable it:

```lua
require("codecompanion").setup({
  integrations = {
    rex = {
      enabled = false,
    },
  },
})
```
