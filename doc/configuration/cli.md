---
description: "Define CLI agents such as Claude Code and Codex, install their hooks and choose how their terminal looks and behaves."
---

# Configuring the CLI

The _CLI interaction_ runs agents such as Claude Code and Codex in a Neovim terminal. CodeCompanion ships with no agents defined, so you add the ones you use.

## Agents

Agents live under `interactions.cli.agents`, and `interactions.cli.agent` sets the default:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      agent = "claude_code",
      agents = {
        claude_code = {
          cmd = "claude",
          args = {},
          description = "Claude Code CLI",
          provider = "terminal",
        },
        codex = {
          cmd = "codex",
          args = {},
          description = "OpenAI Codex CLI",
        },
      },
    },
  },
})
```

| Option | Type | Description |
| --- | --- | --- |
| `cmd` | `string` | The command to run, such as `"claude"` or `"codex"` |
| `args` | `table` | Arguments passed to the command |
| `description` | `string` | Shown in the Action Palette |
| `provider` | `string` | The [provider](#providers) that runs the agent. Defaults to `"terminal"` |

To start an agent other than the default:

```
:CodeCompanionCLI agent=codex <prompt>
```

## Hooks

Without hooks, CodeCompanion can't tell when an agent's turn starts and ends, which limits features such as [code reviews](/usage/code-review). With them, the [event system](/usage/events) reacts to the agent as it works.

Only [Claude Code](https://code.claude.com/docs/en/hooks) is supported. To install its hooks into `~/.claude/settings.json`:

```
:CodeCompanionCLI Install
```

> [!NOTE]
> Hooks are matched on the agent's `cmd`, so it must be `claude`. Run Claude Code once before installing, so its settings file exists

## Providers

A _provider_ decides how an agent is run. The built-in `terminal` provider starts it with `jobstart()` in a Neovim terminal buffer:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      providers = {
        terminal = {
          path = "interactions.cli.providers.terminal",
          description = "Terminal CLI provider",
        },
      },
    },
  },
})
```

### Custom Providers

A provider's `path` can be a CodeCompanion module, any Lua module or a file path. To add your own and use it for an agent:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      providers = {
        my_provider = {
          path = "my_custom.cli_provider",
          description = "My custom CLI provider",
        },
      },
      agents = {
        my_agent = {
          cmd = "my-cli",
          args = {},
          provider = "my_provider",
        },
      },
    },
  },
})
```

An agent whose `provider` isn't in the `providers` table falls back to `terminal`.

## Keymaps

`{` and `}` move between interactions in the CLI buffer. The defaults are:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      keymaps = {
        next_chat = {
          modes = { n = "}" },
          callback = "keymaps.next_chat",
          description = "Open the next interaction",
        },
        previous_chat = {
          modes = { n = "{" },
          callback = "keymaps.previous_chat",
          description = "Open the previous interaction",
        },
      },
    },
  },
})
```

## Insert Mode

To enter insert mode whenever you focus the CLI terminal, and leave it when you move away:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      opts = {
        auto_insert = true,
      },
    },
  },
})
```

## Reloading Buffers

While an agent runs, CodeCompanion watches the directories of your open buffers and reloads any that the agent changes on disk. This is shared with ACP agents and can be configured with:

```lua
require("codecompanion").setup({
  interactions = {
    opts = {
      watcher = {
        enabled = true,
        debounce = 500, -- milliseconds
      },
    },
  },
})
```

## Window

The CLI window takes its layout from `display.chat.window`. Options under `display.cli.window` are merged on top, so you only set what differs:

```lua
require("codecompanion").setup({
  display = {
    cli = {
      window = {
        layout = "vertical",
        width = 0.4,
        height = 0.6,
        opts = {
          list = false,
        },
      },
    },
  },
})
```

To override the size for a single call from Lua:

```lua
require("codecompanion").cli("fix the tests", {
  width = 0.5,
  height = 0.8,
})
```
