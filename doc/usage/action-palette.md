# Using the Action Palette

<p>
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" />
</p>

The _Action Palette_ has been designed to be your entry point for the many configuration options that CodeCompanion offers. It can be opened with `:CodeCompanionActions`.

Once opened, the user can see plugin defined actions such as `Chat` and `Open Chats`. The latter, enabling the user to move between any open chat buffers. These can be turned off in the config by setting `display.action_palette.opts.show_default_actions = false`.

## Default Prompts

The plugin also defines a number of prompts in the form of the prompt library:

- `Explain` - Explain how code in a buffer works
- `Fix Code` - Fix the selected code
- `Explain LSP Diagnostics`  - Explain the LSP diagnostics for the selected code
- `Unit Tests` - Generate unit tests for selected code
- `Generate a Commit Message` - Generate a commit message
- `Workspace File` - Generating a new workspace file and/or creating a group

> [!INFO]
> These can also be called via the cmd line for example `:CodeCompanion /explain`

The plugin also contains an example workflow, `Code Workflow`. See the [workflows section](/usage/workflows) for more information.

The default prompts can be turned off by setting `display.action_palette.show_default_prompt_library = false`.
