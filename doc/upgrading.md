---
description: Guide to upgrading CodeCompanion between versions such as v17.33.0 to v18.0.0
---

# Upgrading CodeCompanion

This document provides a guide for upgrading from one version of CodeCompanion to another.

CodeCompanion follows [semantic versioning](https://semver.org/) and to avoid breaking changes, it is recommended to pin the plugin to a specific version in your Neovim configuration. The [installation guide](installation) provides more information on how to do this.

## v17.33.0 to v18.0.0

### Config

- The biggest change in this release is the renaming of `strategies` to `interactions`. This will only be a breaking change if you specifically reference `codecompanion.strategies` in your configuration. If you do, you'll need to change it to `codecompanion.interactions` ([#2485](https://github.com/olimorris/codecompanion.nvim/pull/2485))
- Previously, built-in slash commands and tools were stored in `/catalog` folders which have now been renamed to `/builtin`. If you reference these in your configuration you'll need to update the paths accordingly ([#2482](https://github.com/olimorris/codecompanion.nvim/pull/2482))
- The `display.chat.child_window` has been renamed `display.chat.floating_window` to better describe what it is
  ([#2452](https://github.com/olimorris/codecompanion.nvim/pull/2452))

### Adapters

- If you have a custom adapter, you'll need to rename `condition` to be `enabled` on any schema items ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569))


### Chat

- Memory has been renamed to rules. Please rename any references to `memory` in your configuration to `rules`. Please refer to the [Rules](/configuration/rules) documentation for more information ([#2440](https://github.com/olimorris/codecompanion.nvim/pull/2440))
- The variable and parameter `#{buffer}{watch}` has been renamed to `#{buffer}{diff}`. This better reflects that an LLM receives a diff of buffer changes with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
- The variable and parameter `#{buffer}{pin}` has now been renamed to `#{buffer}{all}`. This better reflects that the
  entire buffer is sent to the LLM with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
- Passing an adapter as an argument to `:CodeCompanionChat` is now done with `:CodeCompanionChat adapter=<adapter_name>` ([#2437](https://github.com/olimorris/codecompanion.nvim/pull/2437))
- If your chat buffer system prompt is still stored at `opts.system_prompt` you'll need to change it to `interactions.chat.opts.system_prompt` ([#2484](https://github.com/olimorris/codecompanion.nvim/pull/2484))

### Prompt Library

If you have any prompts defined in your config, you'll need to:

- Rename `opts.short_name` to `opts.alias` for each item in order to allow you to call them with
  `require("codecompanion").prompt("docs")` or as slash commands in the chat buffer ([#2471](https://github.com/olimorris/codecompanion.nvim/pull/2471)).

As an example:

::: tabs

== Before

```lua
["my custom prompt"] = {
  strategy = "chat",
  description = "My custom prompt",
  opts = {
    short_name = "p1"
  },
  prompts = {
    -- ...
  },
},
```

== After

```lua
["my custom prompt"] = {
  strategy = "chat",
  description = "My custom prompt",
  opts = {
    alias = "p1"
  },
  prompts = {
    -- ...
  },
},
```

:::

- Change all workflow prompts, replacing `strategy = "workflow"` with `interaction = "chat"` and specifying `opts.is_workflow = true` ([#2487](https://github.com/olimorris/codecompanion.nvim/pull/2487)).

As an example:

::: tabs

== Before

```lua
["my_workflow"] = {
  strategy = "workflow",
  description = "My custom workflow",
  opts = {
    -- ...
  },
  prompts = {
    -- ...
  },
},
```

== After

```lua
["my_workflow"] = {
  interaction = "chat",
  description = "My custom workflow",
  opts = {
    is_workflow = true,
  },
  prompts = {
    -- ...
  },
},
```

:::

- If you don't wish to display any of the built-in prompt library items, you'll need to change `display.action_palette.show_default_prompt_library` to `display.action_palette.show_prompt_library_builtins`

### Tools

If you have any tools in your config, you'll need to rename:

- `requires_approval` to `require_approval_before` ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569))
- `user_confirmation` to `require_confirmation_after` ([#2450](https://github.com/olimorris/codecompanion.nvim/pull/2450))

These now better reflect the timing of each action.
