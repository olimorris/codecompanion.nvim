# Using the Inline Assistant

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" />
</p>

As per the [Getting Started](/getting-started.md#inline-assistant) guide, the Inline Assistant enables you to code directly into a Neovim buffer. Simply run `:CodeCompanion <your prompt>`.

The Assistant has knowledge of your last conversation from a chat buffer. A prompt such as `:CodeCompanion add the new function here` will see the Assistant add a code block directly into the current buffer.

> [!TIP]
> To ensure the LLM has enough context the complete your request, it's recommended to use the `/buffer` prompt

For convenience, you can call prompts from the [prompt library](/configuration/prompt-library) via the Assistant such as `:'<,'>CodeCompanion /buffer what does this file do?`.

## Classification

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed at the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to _replace_ a visual selection. The plugin uses the inline LLM you've specified in your config to determine if the response should:

- _replace_ - replace a visual selection you've made
- _add_ - be added in the current buffer at the cursor position
- _new_ - be placed in a new buffer
- _chat_ - be placed in a chat buffer

## Diff Mode

By default, an inline assistant prompt will trigger the diff feature, showing differences between the original buffer and the changes from the LLM. This can be turned off in your config via the `display.diff.provider` table. You can also choose to accept or reject the LLM's suggestions with the following keymaps:

- `ga` - Accept an inline edit
- `gr` - Reject an inline edit

These keymaps can also be changed in your config via the `strategies.inline.keymaps` table.

