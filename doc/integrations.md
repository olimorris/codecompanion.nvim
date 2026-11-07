---
description: "Connect CodeCompanion to other applications, including herdr, which shows whether CodeCompanion is idle, working or blocked."
---

# Integrations

CodeCompanion fires [events](/usage/events) as it works, so other applications can follow what it's doing. Some integrations are built in.

## herdr

<p align="center">
<video controls muted title="Integration with herdr" src="https://github.com/user-attachments/assets/f58738a2-c0ff-4a3f-9ffa-c8a51efd23be"></video>
</p>

[herdr](https://github.com/herdrdev/herdr) supervises terminal panes and shows which agent is running in each one. When Neovim runs in a herdr pane, or a terminal in the Herdr app, CodeCompanion [reports its state](https://herdr.dev/docs/integrations/#integrate-your-own-agent) to herdr, so the pane sits alongside panes running Claude Code or Codex:

| State | Description |
|---|---|
| `working` | A chat buffer or CLI interaction is waiting on a response, compacting or running tools |
| `blocked` | A tool approval or a question from the LLM is waiting on you |
| `done` | A turn finished whilst you were looking elsewhere (Herdr app only) |
| `idle` | Nothing is in progress |

Every chat buffer and CLI interaction in the Neovim instance counts towards the pane's state, and a `blocked` interaction takes priority. The Herdr app also shows whether a `blocked` pane is waiting on a tool approval or a question.

In the Herdr app, the agents list names the pane after the most recently active chat's title, or `CodeCompanion [branch]` until the chat has one. This is skipped when Neovim's `'title'` option is on, as Neovim then sets the terminal title itself.

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

The Herdr app shows an icon for each agent from its programs table. To give CodeCompanion the Neovim icon, add this to `~/.config/herdr-app/programs.json`:

```json
{
  "programs": {
    "codecompanion": { "name": "CodeCompanion", "icon": "icons/nvim.svg", "tint": true, "tile": "#57a143", "color": "#ffffff" }
  }
}
```

### Limitations

- In the Herdr app, the state doesn't reach herdr when Neovim runs inside tmux or another multiplexer
