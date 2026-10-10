---
description: "Prompt an LLM to write or change code directly in a Neovim buffer, then review its changes as a diff."
---

# Using the Inline Interaction

<p align="center">
  <video controls muted title="Inline interaction demo" src="https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee"></video>
</p>

The _inline interaction_ writes the LLM's response straight into a Neovim buffer, rather than into a chat. To use it:

```
:CodeCompanion <your prompt>
```

Make a visual selection first to send it to the LLM alongside your prompt.

Prompts from the [prompt library](/usage/prompt-library) work too. To generate unit tests for the selected code:

```
:'<,'>CodeCompanion /tests
```

## Adapters

The inline interaction uses the adapter set at `interactions.inline.adapter`. To use a different one for a single prompt, add `adapter=` to it:

```
:'<,'>CodeCompanion adapter=deepseek can you refactor this?
```

## Placement

Along with the code, the LLM decides where it goes:

| Placement | Description |
| --- | --- |
| `replace` | Replace the visual selection |
| `add` | Insert after the cursor |
| `before` | Insert before the cursor |
| `new` | Open a new buffer |
| `chat` | Answer in a chat buffer, for prompts that don't produce code |

So _"create a table of five common text editors"_ lands at the cursor, while _"refactor this function"_ replaces your selection.

## Diff

Changes to an existing buffer are shown as a diff before they're kept. The keymaps are:

| Keymap | Description |
| --- | --- |
| `g1` | Accept the change and stop asking for this buffer |
| `g2` | Accept the change |
| `g3` | Reject the change |

These are shared with tool approvals in the chat buffer and can be changed under `interactions.shared.keymaps`. To skip the diff and write changes straight to the buffer, see [Configuring the Diff](/configuration/diff).

## Editor Context

Editor context shares part of your Neovim session with the LLM. Add it to the prompt with `#{}`:

| Context | Description |
| --- | --- |
| `#{buffer}` | Share the current buffer |
| `#{chat}` | Share the LLM's messages from the last chat buffer |
| `#{clipboard}` | Share the contents of the clipboard |

Combine as many as you need:

```
:CodeCompanion #{buffer} #{clipboard} analyse this code
```

> [!TIP]
> For anything beyond a small change, include `#{buffer}` so the LLM sees the rest of the file

To add your own, see [Editor Context](/configuration/inline#editor-context).
