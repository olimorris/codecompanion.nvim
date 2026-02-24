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

> [!IMPORTANT]
> With the exception of `#{buffer}` and `#{buffers}`, editor context captures a point-in-time snapshot when your message is sent. If the underlying data changes (e.g. new diagnostics, a different quickfix list), simply use the context again in a new message to share the latest state.

## #buffer

> [!NOTE]
> By default, CodeCompanion automatically applies the `{diff}` parameter to all buffers

The `#{buffer}` context shares buffer contents with the LLM. It has two special parameters which control how content is shared, or _synced_, with the LLM, on each turn:

### Basic Usage

- `#{buffer}` - Shares the current buffer (last one you were in)

### Target Specific Buffers

- `#{buffer:init.lua}` - Shares a specific file by name
- `#{buffer:src/main.rs}` - Shares a file by path
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

## #buffers

The _buffers_ context shares all currently open buffers with the LLM. Buffers with excluded buftypes (such as `nofile`, `quickfix`, `prompt`, `popup`) and filetypes (such as `codecompanion`, `help`, `terminal`) are automatically filtered out.

```
#{buffers} can you explain what's going on in these files?
```

## #diagnostics

> [!TIP]
> The [Action Palette](/usage/action-palette) has a pre-built prompt which asks an LLM to explain LSP diagnostics in a visual selection.

The _diagnostics_ context shares any diagnostic information from LSP servers active in the current buffer. This can serve as useful context should you wish to troubleshoot any errors with an LLM.

```
#{diagnostics} can you explain the LSP errors in this file and how to fix them?
```

## #diff

The _diff_ context shares the current git diff with the LLM, including both staged and unstaged changes. This is useful for code review, generating commit messages, or asking for feedback on your recent changes.

```
Sharing the latest git diff with you #{diff}
```

## #messages

The _messages_ context shares Neovim's message history (`:messages`) with the LLM. This is useful when an error has been written to the message history and you want to share it with the LLM for troubleshooting.

```
Can you explain the error I've just observed in Neovim? #{messages}
```

## #quickfix

The _quickfix_ context shares the contents of the quickfix list with the LLM. Files with diagnostics are formatted with smart grouping by Tree-sitter symbols, while file-only entries show the full content. This is useful for sharing compiler errors, search results, or LSP diagnostics across multiple files.

```
The relevant output from my quickfix list has now been shared with you #{quickfix}
```

## #selection

The _selection_ context shares your current or most recent visual selection with the LLM. This is useful for asking about a specific piece of code without sharing the entire buffer. The selection is updated when you open or toggle a CodeCompanion chat buffer.

```
Sharing the relevant code with you #{selection}
```

## #terminal

The _terminal_ context shares the latest output from the last terminal buffer you entered. Subsequent uses capture only new output since the last time it was shared. This is useful for sharing test results, build output, or command-line errors.

```
This was the output in my terminal #{terminal}
```

## #viewport

The _viewport_ context shares with the LLM, exactly what you see on your screen at the point a response is sent (excluding the chat buffer of course).

```
Sharing what I can see in Neovim #{viewport}
```

