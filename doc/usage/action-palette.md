---
description: "Open chats, sessions, prompts and workflows from a single menu in Neovim."
---

# Using the Action Palette

<p>
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" alt="Using the action palette" />
</p>

The _Action Palette_ is a single menu for starting chats, switching between them and running prompts from your [prompt library](/usage/prompt-library). To open it:

```
:CodeCompanionActions
```

Opened from a chat buffer, it lists that chat's keymaps and slash commands instead.

## Actions

The palette starts with these actions:

| Action | Description |
| --- | --- |
| `Chat` | Open a new chat buffer |
| `Open chats ...` | Move to any open chat buffer |
| `Saved sessions ...` | Restore a chat [saved to disk](/configuration/sessions) |
| `Chat with rules ...` | Open a chat buffer with a [rule group](/usage/chat-buffer/rules) loaded |

To hide them, set `display.action_palette.opts.show_preset_actions = false`.

## Built-in Prompts

Below the actions are the prompts that ship with CodeCompanion:

| Prompt | Alias | Description |
| --- | --- | --- |
| `Commit message` | `commit` | Generate a commit message |
| `Explain code` | `explain` | Explain how code in a buffer works |
| `Explain LSP diagnostics` | `lsp` | Explain the LSP diagnostics for the selected code |
| `Fix code` | `fix` | Fix the selected code |
| `Help with CodeCompanion` | `help` | Answer a question from CodeCompanion's documentation |
| `Inline prompt` | | Prompt the LLM from inside a Neovim buffer |
| `Unit tests` | `tests` | Generate unit tests for the selected code |
| `Code workflow` | | Run the built-in [workflow](/usage/workflows) |

Prompts with an alias can also be run from the command line:

```
:CodeCompanion /explain
```

To hide the built-in prompts, set `display.action_palette.opts.show_preset_prompts = false`.

## Refreshing

The palette caches its items. After editing your prompt library, reload them with:

```
:CodeCompanionActions Refresh
```
