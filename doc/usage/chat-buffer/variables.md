# Using Variables

<p align="center">
  <img src="https://github.com/user-attachments/assets/642ef2df-f1c4-41c4-93e2-baa66d7f0801" />
</p>

Variables allow you to share Neovim context with an LLM. Typing `#` in the chat buffer will trigger a code completion menu. Alternatively, you can type variables manually. After the response is sent to the LLM, you will see the variable output tagged as a context item in the chat buffer.

Custom variables can be shared in the chat buffer by adding them to the `strategies.chat.variables` table in your configuration.

## #buffer

The _#{buffer}_ variable shares the full contents from the last buffer that the user was in (as determined by `BufEnter`). To select multiple buffers, it's recommended to use the _/buffer_ slash command.

By default, buffers are [watched](/usage/chat-buffer/index#context) to enable updated content to be automatically shared with the LLM. They can also be pinned:

- `#{buffer}{watch}` - Sends the changes in the underlying buffer to the LLM
- `#{buffer}{pin}` - Sends the entire buffer (regardless of changes) to the LLM

You can also share specific buffers using the completion menus with something like `#{buffer:http/init.lua}`.

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

