# Using Variables

<img src="https://github.com/user-attachments/assets/642ef2df-f1c4-41c4-93e2-baa66d7f0801" />

Variables allow you to share data about the current state of Neovim with an LLM. Simply type `#` in the chat buffer and trigger code completion if you're not using blink.cmp or nvim-cmp. Alternatively, type the variables manually. After the response is sent to the LLM, you should see the variable output tagged as a reference in the chat buffer.

Custom variables can be shared by adding them to the `strategies.chat.variables` table in your configuration.

## #buffer

The _#buffer_ variable shares the full contents from the buffer that the user was last in when they initiated `:CodeCompanionChat`. To select another buffer, use the _/buffer_ slash command. These buffers can be [pinned or watched](/usage/chat-buffer/index#references) to enable updated content to be automatically shared with the LLM.

## #lsp

> [!TIP]
> The [Action Palette](/usage/action-palette) has a pre-built prompt which asks an LLM to explain LSP diagnostics in a
> visual selection

The _#lsp_ variable shares any information from the LSP servers that active in the current buffer. This can serve as useful context should you wish to troubleshoot any errors with an LLM.

## #viewport

The _#viewport_ variable shares with the LLM, exactly what you see on your screen at the point a response is sent (excluding the chat buffer of course).

