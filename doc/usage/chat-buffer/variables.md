# Using Variables

> [!IMPORTANT]
> As of `v17.5.0`, variables must be wrapped in curly braces, such as `#{buffer}` or `#{lsp}`

<p align="center">
  <img src="https://github.com/user-attachments/assets/642ef2df-f1c4-41c4-93e2-baa66d7f0801" />
</p>

Variables allow you to share data about the current state of Neovim with an LLM. Simply type `#` in the chat buffer and trigger code completion if you're not using blink.cmp or nvim-cmp (or coc.nvim). Alternatively, type the variables manually. After the response is sent to the LLM, you should see the variable output tagged as a reference in the chat buffer.

Custom variables can be shared by adding them to the `strategies.chat.variables` table in your configuration.

## #buffer

> [!NOTE]
> As of [v16.2.0](https://github.com/olimorris/codecompanion.nvim/releases/tag/v16.2.0), buffers are now watched by default

The _#{buffer}_ variable shares the full contents from the buffer that the user was last in when they initiated `:CodeCompanionChat`. To select another buffer, use the _/buffer_ slash command. These buffers can be [pinned or watched](/usage/chat-buffer/index#references) to enable updated content to be automatically shared with the LLM:

- `#{buffer}{pin}` - To pin the current buffer
- `#{buffer}{watch}` - To watch the current buffer

To pin or watch buffers by default, you can add this configuration:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      variables = {
        ["buffer"] = {
          opts = {
            default_params = 'pin', -- or 'watch'
          },
        },
      },
    },
  },
})
```

## #lsp

> [!TIP]
> The [Action Palette](/usage/action-palette) has a pre-built prompt which asks an LLM to explain LSP diagnostics in a
> visual selection

The _lsp_ variable shares any information from the LSP servers that active in the current buffer. This can serve as useful context should you wish to troubleshoot any errors with an LLM.

## #viewport

The _viewport_ variable shares with the LLM, exactly what you see on your screen at the point a response is sent (excluding the chat buffer of course).

