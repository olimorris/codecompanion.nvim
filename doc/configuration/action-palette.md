---
description: "Change how the Action Palette looks, which picker it uses and which built-in items it lists."
---

# Configuring the Action Palette

<p align="center">
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" alt="Action Palette">
</p>

The [Action Palette](/usage/action-palette) lists CodeCompanion's actions, such as starting a chat or switching to an open one, alongside the prompts from the [prompt library](/configuration/prompt-library).

## Layout

The palette is configured under `display.action_palette`. The defaults are:

```lua
require("codecompanion").setup({
  display = {
    action_palette = {
      width = 95,
      height = 10,
      prompt = "Prompt ", -- Shown when CodeCompanion asks for your input
      provider = "default", -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"
      opts = {
        show_preset_actions = true,
        show_preset_prompts = true,
        title = "CodeCompanion actions",
      },
    },
  },
})
```

If you don't set a `provider`, CodeCompanion uses the first one installed out of [Telescope](https://github.com/nvim-telescope/telescope.nvim), [fzf-lua](https://github.com/ibhagwan/fzf-lua), [mini.pick](https://github.com/nvim-mini/mini.pick) and [Snacks](https://github.com/folke/snacks.nvim), then falls back to `default`. `width` and `height` only apply to the `default` provider.

## Options

The `opts` table takes:

| Option | Description |
| --- | --- |
| `show_preset_actions` | Show the [actions](/usage/action-palette#actions), such as `Chat` and `Open chats ...` |
| `show_preset_prompts` | Show the [prompts](/usage/action-palette#built-in-prompts) that ship with CodeCompanion |
| `title` | The title of the palette |
