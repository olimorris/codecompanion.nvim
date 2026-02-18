---
description: Guide to upgrading CodeCompanion between versions such as v17.33.0 to v18.0.0
---

# Upgrading CodeCompanion

This document provides a guide for upgrading from one version of CodeCompanion to another.

CodeCompanion follows [semantic versioning](https://semver.org/) and to avoid breaking changes, it is recommended to pin the plugin to a specific version in your Neovim configuration. The [installation guide](installation) provides more information on how to do this.

## v18.6.0 to v19.0.0

- The Super Diff has now been removed from CodeCompanion ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- CodeCompanion now only supports a built-in diff which is enabled by default ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600)), dropping support for Mini.Diff

### Adapters

- For the Claude Code adapter to work, you'll need to ensure you have Zed's
  [claude-agent-acp](https://github.com/zed-industries/claude-agent-acp) adapter installed. This has been renamed from _claude-code-acp_ in recent times

### Config

- Diff keymaps have moved from `interactions.inline.keymaps` to `interactions.shared.keymaps` ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- All diff config has moved to `display.diff` ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- `variables` have been renamed to `editor_context` and the config paths are now `interactions.chat.editor_context` and `interactions.inline.editor_context` ([#2719](https://github.com/olimorris/codecompanion.nvim/pull/2719))
- Across _editor context_, _slash commands_ and _tools_, `callback` has been replaced by `path` for string values (module paths and file paths). `callback` is still used for function values, however

### Prompt Library

- The location of rules within a prompt library item has changed from `opts.rules` to `rules`. They now also support workflows:

```markdown
---
name: Oli's test workflow
strategy: chat
description: Workflow test prompt
rules:
  - test_rule
---
```

## v17.33.0 to v18.0.0

### Config

- The biggest change in this release is the renaming of `strategies` to `interactions`. This will only be a breaking change if you specifically reference `codecompanion.strategies` in your configuration. If you do, you'll need to change it to `codecompanion.interactions` ([#2485](https://github.com/olimorris/codecompanion.nvim/pull/2485))
- Previously, built-in slash commands and tools were stored in `/catalog` folders which have now been renamed to `/builtin`. If you reference these in your configuration you'll need to update the paths accordingly ([#2482](https://github.com/olimorris/codecompanion.nvim/pull/2482))
- Workspaces have now been removed from the plugin. Please use [Rules](configuration/rules) instead.

### Adapters

- If you have a custom adapter, you'll need to rename `condition` to be `enabled` on any schema items ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569)):

```lua
return {
  schema = {
    ["reasoning.effort"] = {
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      condition = function(self) -- [!code --]
      enabled = function(self) -- [!code ++]
        --
      end,
    },
  }
}
```

- The default adapters on the **Anthropic** and **Gemini** adapters have changed to `claude-sonnet-4-5-20250929` and `gemini-3-pro-preview`, respectively ([#2494](https://github.com/olimorris/codecompanion.nvim/pull/2494))
- If you wish to hide the adapters that come with CodeCompanion, `adapter.[acp|http].opts.show_defaults` has been renamed to `adapter.[acp|http].opts.show_presets` for both HTTP and ACP adapters ([#2497](https://github.com/olimorris/codecompanion.nvim/pull/2497))

### Chat

- Memory has been renamed to rules. Please rename any references to `memory` in your configuration to `rules`. Please refer to the [Rules](/configuration/rules) documentation for more information ([#2440](https://github.com/olimorris/codecompanion.nvim/pull/2440))
- `default_memory` has been renamed to `autoload` ([#2509](https://github.com/olimorris/codecompanion.nvim/pull/2509))
---
- The variable and parameter `#{buffer}{watch}` has been renamed to `#{buffer}{diff}`. This better reflects that an LLM receives a diff of buffer changes with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
- The variable and parameter `#{buffer}{pin}` has now been renamed to `#{buffer}{all}`. This better reflects that the
  entire buffer is sent to the LLM with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
---
- Passing an adapter as an argument to `:CodeCompanionChat` is now done with `:CodeCompanionChat adapter=<adapter_name>` ([#2437](https://github.com/olimorris/codecompanion.nvim/pull/2437))
- If your chat buffer system prompt is still stored at `opts.system_prompt` you'll need to change it to `interactions.chat.opts.system_prompt` ([#2484](https://github.com/olimorris/codecompanion.nvim/pull/2484))

### Prompt Library

If you have any prompts defined in your config, you'll need to:

- Rename `opts.short_name` to `opts.alias` for each item in order to allow you to call them with `require("codecompanion").prompt("my_prompt")` or as slash commands in the chat buffer ([#2471](https://github.com/olimorris/codecompanion.nvim/pull/2471)).

```lua
["my custom prompt"] = {
  strategy = "chat",
  description = "My custom prompt",
  opts = {
    short_name = "my_prompt", -- [!code --]
    alias = "my_prompt", -- [!code ++]
  },
  prompts = {
    -- ...
  },
},
```

- Change all workflow prompts, replacing `strategy = "workflow"` with `interaction = "chat"` and specifying `opts.is_workflow = true` ([#2487](https://github.com/olimorris/codecompanion.nvim/pull/2487)).

```lua
["my_workflow"] = {
  strategy = "workflow", -- [!code --]
  interaction = "chat", -- [!code ++]
  description = "My custom workflow",
  opts = {
    is_workflow = true, -- [!code ++]
  },
  prompts = {
    -- ...
  },
},
```

- If you don't wish to display any of the built-in prompt library items, you'll need to change `display.action_palette.show_default_prompt_library` to `display.action_palette.show_preset_prompts` ([#2499](https://github.com/olimorris/codecompanion.nvim/pull/2499))

### Tools

If you have any tools in your config, you'll need to rename:

- `requires_approval` to `require_approval_before` ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569))
- `user_confirmation` to `require_confirmation_after` ([#2450](https://github.com/olimorris/codecompanion.nvim/pull/2450))

These now better reflect the timing of each action.

### UI

- The `display.chat.child_window` has been renamed `display.chat.floating_window` to better describe what it is ([#2452](https://github.com/olimorris/codecompanion.nvim/pull/2452))
- The `display.action_palette.opts.show_default_actions` has been renamed to be `display.action_palette.opts.show_preset_actions` ([#2499](https://github.com/olimorris/codecompanion.nvim/pull/2499))
