---
description: "Connect CodeCompanion to other applications, including herdr, which shows whether CodeCompanion is idle, working or blocked."
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
