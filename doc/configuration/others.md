---
description: "Configure miscellaneous CodeCompanion options: response language, log level, per-project config files, and restricting code from being sent to LLMs."
---

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

## Context Formatters

You can customise how a buffer and file's content is shared with an LLM with context formatters.

**Example:** A Jupyter Notebook is a large JSON document with base64 images embedded in it which can erode an LLM's context window.

A context formatter modifies a file's content before it is shared with an LLM. This is the case whether the file was attached with `/file`, opened as a buffer and attached with `/buffer`, pulled in by a rules file, or re-read to produce a [sync](/configuration/chat-buffer#syncing) diff.

A formatter is a `format(raw, path)` function which returns the content the LLM should see, or the path to a module which returns one. Returning nothing leaves the content untouched:

````lua
require("codecompanion").setup({
  context = {
    formatters = {
      ipynb = false, -- Disable the built-in notebook formatter
      sqlite = function(raw, path)
        -- Return the content the LLM should see for this file
      end,
      -- Or the path to any module which returns a table with a `format` function.
      -- The built-in notebook formatter lives at
      -- "codecompanion.context.formatters.builtin.jupyter_notebook"
      log = "my_plugin.context.formatters.log",
    },
  },
})
````

Formatters are responsible for their own formatting, so content they return is passed through as-is. Content they do not touch is wrapped in a code fence when attached to the chat, and buffers additionally get line numbers. Neither is applied when content is re-read for a sync diff, as the diff itself is fenced.

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

