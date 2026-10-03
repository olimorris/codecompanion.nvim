---
description: "Edit code directly in a Neovim buffer with CodeCompanion's inline interaction, with diff review and visual selections."
---

# Using the Inline Interaction

<p align="center">
  <video controls muted title="Inline interaction demo" src="https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee"></video>
</p>

As per the [Getting Started](/getting-started#editing-inline) guide, the inline interaction lets the LLM edit the current buffer directly. Run `:CodeCompanion <your prompt>` to let it edit the whole buffer, or make a visual selection first to limit its edits to those lines. Running `:CodeCompanion` on its own opens an input box to write your prompt in, with the adapter and model that will answer in its title.

You can also call inline prompts from the [prompt library](/configuration/prompt-library) by their alias, such as `:'<,'>CodeCompanion /docstrings`.

## Adapters

Press `ga` in the input box to pick an adapter and model. Your choice is remembered for that buffer, so later inline prompts in it use the same adapter and model until you pick again. Other buffers keep using `interactions.inline.adapter`.

For a one-off, include the adapter in your prompt with `adapter=*`. For example `:<','>CodeCompanion adapter=deepseek can you refactor this?`. This isn't remembered, and can be combined with editor context.

## How Edits Work

The current buffer is shared with the LLM, which edits it by calling the `edit_file` tool, once per change. What it can edit depends on your selection:

- **No selection** - The LLM can edit anything it's been shared
- **Visual selection** - The LLM can only edit the selected lines. The rest of the buffer is still shared, so it can see imports and surrounding code

If a buffer is over the [context limit](/configuration/inline#context-limit), only the lines around your cursor, or your selection, are shared. Without a selection, those are also the only lines the LLM can edit.

If an edit fails, for example because the text it targets isn't in the buffer, the error is sent back to the LLM once so it can try again. If it fails a second time, nothing is changed and the error is logged.

If you ask a question rather than for a change, such as _"what does this function do?"_, the LLM replies without editing and the reply opens in a float. Moving the cursor or pressing `q` closes it, and `<C-w>w` moves into it to scroll a long reply.

## Diff Mode

By default, the LLM's edits are shown as a diff in the buffer, which you can review a hunk at a time. Press `?` in the diff to see these keymaps:

| Keymap | Action |
|---|---|
| `}` / `{` | Move to the next or previous hunk |
| `ga` | Accept the hunk under the cursor |
| `gr` | Reject the hunk under the cursor |
| `u` | Undo the last hunk you accepted or rejected |
| `g2` | Accept the hunks that are left |
| `g3` | Reject the hunks that are left |
| `g1` | Accept the hunks that are left, and every future edit to this buffer |

Once every hunk has been accepted or rejected, the diff closes. Pressing `u` afterwards undoes the whole edit in one step, however many hunks you resolved, and rejecting every hunk leaves nothing to undo. The diff can be turned off with `display.diff.enabled`, the banner above the current hunk hidden with `display.diff.show_banner`, and the keymaps changed in `interactions.shared.keymaps`.

## Editor Context

The inline interaction allows you to send context alongside your prompt via the notion of editor context. That is, context that relates to your current Neovim session:

- `chat` - shares the LLM's messages from the last chat buffer
- `clipboard` - shares the data on your clipboard with the LLM

Include them in your prompt, for example `:CodeCompanion #{clipboard} use this function in the buffer`. Multiple context items can be sent as part of the same prompt, and you can add your own as per the [configuration](/configuration/inline#editor-context).

## Limitations

- The adapter's model must support tool calling. Adapters that don't, such as _xai_, are refused
- A selection is limited by whole lines, so selecting part of a line lets the LLM edit all of it
- If the buffer changes while the LLM is responding, its edits are discarded

