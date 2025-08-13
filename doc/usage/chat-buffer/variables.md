# Using Variables

<p align="center">
  <img src="https://github.com/user-attachments/assets/642ef2df-f1c4-41c4-93e2-baa66d7f0801" />
</p>

Variables allow you to share Neovim context with an LLM. Typing `#` in the chat buffer will trigger a code completion menu. Alternatively, you can type variables manually. After the response is sent to the LLM, you will see the variable output tagged as a context item in the chat buffer.

Custom variables can be shared in the chat buffer by adding them to the `strategies.chat.variables` table in your configuration.

## Basic Usage

Variables use the `#{variable_name}` syntax to dynamically insert content into your chat. For example `#{buffer}`. Variables are processed when you send your message to the LLM.

## #buffer

> [!IMPORTANT]
> By default, CodeCompanion automatically applies `{watch}` to all buffers

The `#{buffer}` variable shares buffer contents with the LLM. It has two special parameters which control how content is shared with the LLM:

**`{pin}`** - Sends the entire buffer content to the LLM whenever the buffer changes. Use this when you want the LLM to always have the complete, up-to-date file context.

**`{watch}`** - Sends only the changed portions of the buffer to the LLM. Use this for large files where you only want to share incremental changes to reduce token usage.


### Basic Usage

- `#{buffer}` - Shares the current buffer (last one you were in)

### Target Specific Buffers

- `#{buffer:init.lua}` - Shares a specific file by name
- `#{buffer:src/main.rs}` - Shares a file by relative path
- `#{buffer:utils}` - Shares a file containing "utils" in the path

### With Parameters

- `#{buffer}{pin}` - Pins the buffer (sends entire buffer on changes)
- `#{buffer}{watch}` - Watches for changes (sends only changes)
- `#{buffer:config.lua}{pin}` - Combines targeting with parameters

### Multiple Buffers

```
Compare #{buffer:old_file.js} with #{buffer:new_file.js} and explain the differences.
```

> **Note:** For selecting multiple buffers with more control, use the `/buffer` slash command.

## #lsp

> [!TIP]
> The [Action Palette](/usage/action-palette) has a pre-built prompt which asks an LLM to explain LSP diagnostics in a
> visual selection

The _lsp_ variable shares any information from the LSP servers that active in the current buffer. This can serve as useful context should you wish to troubleshoot any errors with an LLM.

## #viewport

The _viewport_ variable shares with the LLM, exactly what you see on your screen at the point a response is sent (excluding the chat buffer of course).

