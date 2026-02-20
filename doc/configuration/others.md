# Other Configuration Options

## Language

If you use the default system prompt, you can specify which language an LLM should respond in by changing the `opts.language` option:

```lua
require("codecompanion").setup({
  opts = {
    language = "English",
  },
}),
```

Of course, if you have your own system prompt you can specify your own language for the LLM to respond in.

## Log Level

> [!IMPORTANT]
> By default, logs are stored at `~/.local/state/nvim/codecompanion.log`

When it comes to debugging, you can change the level of logging which takes place in the plugin as follows:

```lua
require("codecompanion").setup({
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
  },
}),
```

## Per-Project Configuration

Working across multiple projects, it can be useful to set different CodeCompanion configurations.

The plugin allows you to specify a list of files which it will look for in the current working directory. If any of the files are found, they will be loaded and merged with the default configuration.

Alternatively, you can specify a directory as a key and the configuration as the value.

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

File-based configuration must return a valid Lua table. For example:

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

## Sending Code

> [!IMPORTANT]
> Whilst the plugin makes every attempt to prevent code from being sent to the LLM, use this option at your own risk

You can prevent any code from being sent to the LLM with:

```lua
require("codecompanion").setup({
  opts = {
    send_code = false,
  },
}),
```

