# Using the Inline Assistant

<p align="center">
  <video controls muted src="https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee"></video>
</p>

As per the [Getting Started](/getting-started.md#inline-assistant) guide, the inline assistant enables you to code directly into a Neovim buffer. Simply run `:CodeCompanion <your prompt>`, or make a visual selection to send that as context to the LLM alongside your prompt.

For convenience, you can call prompts from the [prompt library](/configuration/prompt-library) via the assistant. For example, `:'<,'>CodeCompanion /tests` would ask the LLM to create some unit tests from the selected text.

## Variables

> [!TIP]
> To ensure the LLM has enough context to complete a complex ask, it's recommended to use the `buffer` variable

The inline assistant allows you to send context alongside your prompt via the notion of variables:

- `buffer` - shares the contents of the current buffer
- `chat` - shares the LLM's messages from the last chat buffer

Simply include them in your prompt. For example `:CodeCompanion #{buffer} add a new method to this file`. Multiple variables can be sent as part of the same prompt. You can even add your own custom variables as per the [configuration](/configuration/inline-assistant#variables).

## Adapters

You can specify a different adapter to that in the configuration (`strategies.inline.adapter`) when sending an inline prompt. Simply include the adapter name as the first word in the prompt. For example `:<','>CodeCompanion deepseek can you refactor this?`. This approach can also be combined with variables.

## Classification

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed at the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to _replace_ a visual selection. The plugin uses the inline LLM you've specified in your config to determine if the response should:

- _replace_ - replace a visual selection you've made
- _add_ - be added in the current buffer at the cursor position
- _before_ - to be added in the current buffer before the cursor position
- _new_ - be placed in a new buffer
- _chat_ - be placed in a chat buffer

## Diff Mode

By default, an inline assistant prompt will trigger the diff feature, showing differences between the original buffer and the changes made by the LLM. This can be turned off in your config via the `display.diff.provider` table. You can also choose to accept or reject the LLM's suggestions with the following keymaps:

- `ga` - Accept an inline edit
- `gr` - Reject an inline edit

These keymaps can also be changed in your config via the `strategies.inline.keymaps` table.

