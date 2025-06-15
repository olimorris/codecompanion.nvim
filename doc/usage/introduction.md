# Using CodeCompanion

CodeCompanion continues to evolve with regular frequency. This page will endeavour to serve as focal point for providing useful productivity tips for the plugin.

## Copying code from a chat buffer

The fastest way to copy an LLM's code output is with `gy`. This will yank the nearest codeblock.

## Applying an LLM's edits to a buffer or file

The [@insert_edit_into_file](/usage/chat-buffer/agents#files) tool, combined with the [#buffer](/usage/chat-buffer/variables.html#buffer) variable or [/buffer](/usage/chat-buffer/slash-commands.html#buffer) slash command, enables an LLM to modify code in a Neovim buffer. This is especially useful if you do not wish to manually apply an LLM's suggestions yourself. Simply tag it in the chat buffer with `@files` or `@insert_edit_into_file`.

## Run tests from the chat buffer

The [cmd_runner](/usage/chat-buffer/agents#cmd-runner) tool enables an LLM to execute commands on your machine. This can be useful if you wish the LLM to run a test suite on your behalf and give insight on failing cases. Simply tag the `@cmd_runner` in the chat buffer and ask it run your tests.

## Navigating between responses in the chat buffer

You can quickly move between responses in the chat buffer using `[[` or `]]`.

## Quickly accessing a chat buffer

The `:CodeCompanionChat Toggle` command will automatically create a chat buffer if one doesn't exist, open the last chat buffer or hide the current chat buffer.

When in a chat buffer, you can cycle between other chat buffers with `{` or `}`.

