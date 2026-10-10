---
description: "Set the language LLMs respond in, the log level, per-project config and whether code can be sent to an LLM."
---

# Configuring Other Options

## Language

The default system prompt asks the LLM to respond in English. To change the language:

```lua
require("codecompanion").setup({
  opts = {
    language = "French",
  },
})
```

If you've written your own system prompt, set the language in it instead.

## Log Level

Logs are written to `codecompanion.log` in `stdpath("log")`, which is `~/.local/state/nvim` on most systems. To log more detail when debugging:

```lua
require("codecompanion").setup({
  opts = {
    log_level = "DEBUG", -- Can be "TRACE", "DEBUG", "INFO", "WARN" or "ERROR"
  },
})
```

The default is `ERROR`.

## Per-Project Configuration

When you work across several projects, each can have its own CodeCompanion config. List files to look for in the current working directory, or key a config by directory:

::: code-group

```lua [Files]
require("codecompanion").setup({
  opts = {
    per_project_config = {
      files = {
        ".codecompanion",
        ".codecompanion.lua",
      },
    },
  },
})
```

```lua [Dirs]
require("codecompanion").setup({
  opts = {
    per_project_config = {
      paths = {
        ["~/Code/Python/New-Startup"] = {
          interactions = {
            chat = {
              adapter = {
                name = "copilot",
                model = "claude-opus-4.6",
              },
            },
          },
        },
      },
    },
  },
})
```

:::

A directory only matches when it's the working directory itself, not a parent of it. A matching config is merged over your own, and a file takes precedence over a directory if both match. A file must return a Lua table:

```lua
return {
  interactions = {
    chat = {
      adapter = {
        name = "copilot",
        model = "claude-sonnet-4.6",
      },
      tools = {
        opts = {
          default_tools = {
            "memory",
          },
        },
      },
    },
  },
}
```

To turn per-project config off, set `opts.per_project_config.enabled = false`.

> [!NOTE]
> Per-project config is read once, when `setup()` runs, so changing directory afterwards doesn't load another project's config

## Sending Code

> [!WARNING]
> CodeCompanion makes every attempt to stop code reaching the LLM, but use this option at your own risk

To stop editor context, slash commands and prompts marked as containing code from being sent to the LLM:

```lua
require("codecompanion").setup({
  opts = {
    send_code = false,
  },
})
```

`send_code` can also be a function that returns a boolean, so you can decide per request.
