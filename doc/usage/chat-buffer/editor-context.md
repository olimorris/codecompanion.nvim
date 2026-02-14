---
description: Learn how to add context related to buffers and data in your editor, to the chat buffer
---

# Using Editor Context

<p align="center">
  <img src="https://github.com/user-attachments/assets/642ef2df-f1c4-41c4-93e2-baa66d7f0801" />
</p>

Editor context allows you to dynamically insert Neovim context into your chat messages using the `#{context}` syntax. They're processed when you send your message to the LLM, automatically including relevant content like buffer contents, LSP diagnostics, or your current viewport. Type `#` in the chat buffer to see available context through code completion, or type them manually.

Custom context can be shared in the chat buffer by adding them to the `interactions.chat.editor_context` table in your configuration.

## Basic Usage

Editor context uses the `#{context}` syntax to dynamically insert content into your chat, such as `#{buffer}`. Editor context is processed when you send your message to the LLM.

## #buffer

> [!IMPORTANT]
> By default, CodeCompanion automatically applies the `{diff}` parameter to all buffers

The `#{buffer}` context shares buffer contents with the LLM. It has two special parameters which control how content is shared, or _synced_, with the LLM, on each turn:

### Basic Usage

- `#{buffer}` - Shares the current buffer (last one you were in)

### Target Specific Buffers

- `#{buffer:init.lua}` - Shares a specific file by name
- `#{buffer:src/main.rs}` - Shares a file by relative path
- `#{buffer:utils}` - Shares a file containing "utils" in the path

### With Parameters

**`{diff}`** - Sends only the changed portions of the buffer to the LLM. Use this for large files where you only want to share incremental changes to reduce token usage. This is the default option in CodeCompanion.

**`{all}`** - Sends all of the buffer content to the LLM whenever the buffer changes. Use this when you want the LLM to always have the complete, up-to-date file context.

Can be used in combination with targeting a specific buffer:

- `#{buffer}{diff}` - Sends only changed portions of the buffer
- `#{buffer}{all}` - Sends entire buffer on any change
- `#{buffer:config.lua}{all}` - Combines targeting with parameters

### Multiple Buffers

> [!NOTE]
> For selecting multiple buffers with more control, use the `/buffer` slash command.

```
Compare #{buffer:old_file.js} with #{buffer:new_file.js} and explain the differences.
```

## #lsp

> [!TIP]
> The [Action Palette](/usage/action-palette) has a pre-built prompt which asks an LLM to explain LSP diagnostics in a visual selection.

The _lsp_ context shares any information from the LSP servers that active in the current buffer. This can serve as useful context should you wish to troubleshoot any errors with an LLM.

## #viewport

The _viewport_ context shares with the LLM, exactly what you see on your screen at the point a response is sent (excluding the chat buffer of course).

