---
description: "Connect CodeCompanion.nvim to other applications via its Neovim events catalog, including built-in herdr support that reports agent state as idle, working, or blocked."
---

# Integrations

CodeCompanion enables integrations with many applications based on its rich [events](/usage/events) catalog.

## herdr

<p align="center">
<video controls muted title="Integration with herdr" src="https://github.com/user-attachments/assets/f58738a2-c0ff-4a3f-9ffa-c8a51efd23be"></video>
</p>

CodeCompanion supports [herdr](https://github.com/herdrdev/herdr) out of the box with a direct integration allowing it to appear as an agent. CodeCompanion fully supports herdr's lifecycle for [reporting semantic state](https://herdr.dev/docs/integrations/#integrate-your-own-agent).

It's enabled by default but can be disabled with:

```lua
require("codecompanion").setup({
  integrations = {
    herdr = {
      enabled = false,
    },
  },
})
```
