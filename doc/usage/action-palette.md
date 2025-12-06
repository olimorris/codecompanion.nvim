---
description: How to use the action palette in CodeCompanion
---

# Using the Action Palette

<p>
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" />
</p>

The _Action Palette_ has been designed to be your entry point for the many configuration options that CodeCompanion offers. It can be opened with `:CodeCompanionActions`.

Once opened, the user can see plugin defined actions such as `Chat` and `Open Chats`. The latter, enabling the user to move between any open chat buffers. These can be turned off in the config by setting `display.action_palette.opts.show_default_actions = false`.

## Built-in Prompts

The plugin also defines a number of prompts in the form of the prompt library:

- `Commit message` - Generate a commit message
- `Explain code` - Explain how code in a buffer works
- `Explain LSP diagnostics`  - Explain the LSP diagnostics for the selected code
- `Fix code` - Fix the selected code
- `Unit tests` - Generate unit tests for selected code

> [!INFO]
> These can also be called via the cmd line with their `alias`, for example `:CodeCompanion /explain`

The plugin also contains two built-in workflows, `Code workflow` and `Edit test repeat workflow`. See the [workflows section](/usage/workflows) for more information.

The built-in prompts can be turned off by setting `display.action_palette.show_prompt_library_builtins = false`.

You can also refresh the markdown prompts in your prompt library with `:CodeCompanionActions refresh`
