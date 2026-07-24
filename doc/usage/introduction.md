---
description: "Tips and tricks for getting the most out of CodeCompanion in Neovim — keyboard shortcuts, context management, output handling, and productivity patterns."
---

# Using CodeCompanion

CodeCompanion continues to evolve with regular frequency. This page will endeavour to serve as focal point for providing useful productivity tips for the plugin.

## Apply an LLM's edits to a buffer/file

The [@insert_edit_into_file](/usage/chat-buffer/agents-tools#files) tool, combined with the [#buffer](/usage/chat-buffer/editor-context#buffer) editor context or [/buffer](/usage/chat-buffer/slash-commands#buffer) slash command, enables an LLM to modify code in a Neovim buffer. This is especially useful if you do not wish to manually apply an LLM's suggestions yourself. Simply tag it in the chat buffer with `@files` or `@insert_edit_into_file`.

## Code review an LLM/agent's changes

You can [review an LLM or agent's changes](/usage/code-reviews) like a pull request. `:CodeCompanionCodeReview` opens every change in the quickfix list, one entry per hunk. You can step through them, leave in place comments with `:CodeCompanionCodeReview Comment` and then share the review in a chat buffer with the [#{code_review}](/usage/chat-buffer/editor-context#code_review) context.

To navigate to the files an agent has edited or created, use `:CodeCompanionChat Changes` to open them in the quickfix list. Every file the LLM touches in your Neovim session is tracked, across chats and the CLI.

## Copying code from a chat buffer

The fastest way to copy an LLM's code output is with `gy`. This will yank the nearest codeblock.

## Navigating between responses in the chat buffer

You can quickly move between responses in the chat buffer using `[[` or `]]`.

## Quickly accessing a chat buffer

The `:CodeCompanionChat Toggle` command will automatically create a chat buffer if one doesn't exist, open the last chat buffer or hide the current chat buffer.

When in a chat buffer, you can cycle between other chat buffers with `{` or `}`.

By default, opening or cycling to a chat hides whichever chat is currently visible. If you'd rather keep chats per tab — so a chat opened in tab A is never closed or stolen by activity in tab B — set `display.chat.window.pertab = true` in your config. With that enabled, `{` / `}` only cycles through chats that are visible in the current tab or not currently visible anywhere, and `:CodeCompanionChat Toggle` jumps to the existing tab when the chat lives there.

## Run tests from the chat buffer

The [run_command](/usage/chat-buffer/agents-tools#run-command) tool enables an LLM to execute commands on your machine. This can be useful if you wish the LLM to run a test suite on your behalf and give insight on failing cases. Simply tag the `@run_command` in the chat buffer and ask it run your tests.

