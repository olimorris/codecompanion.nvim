# Configuring the Action Palette

<p align="center">
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" alt="Action Palette">
</p>

The Action Palette holds plugin specific items like the ability to launch a chat buffer and the currently open chat buffers alongside displaying the prompts from the [Prompt Library](prompt-library).

## Layout

> [!NOTE]
> The Action Palette also supports [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), [fzf_lua](https://github.com/ibhagwan/fzf-lua), [mini.pick](https://github.com/echasnovski/mini.pick) and [snacks.nvim](https://github.com/folke/snacks.nvim)

You can change the appearance of the chat buffer by changing the `display.action_palette` table in your configuration:

```lua
require("codecompanion").setup({
  display = {
    action_palette = {
      width = 95,
      height = 10,
      prompt = "Prompt ", -- Prompt used for interactive LLM calls
      provider = "default", -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks". If not specified, the plugin will autodetect installed providers.
      opts = {
        show_default_actions = true, -- Show the default actions in the action palette?
        show_default_prompt_library = true, -- Show the default prompt library in the action palette?
      },
    },
  },
}),
```
