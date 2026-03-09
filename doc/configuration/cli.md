---
description: Learn how to configure agents via the Command-Line Interface (CLI) in CodeCompanion.nvim
---

# Configuring the Command-Line Interface (CLI)

## Agents

To use the CLI interaction, you need to define at least one agent in your configuration:

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
      },
    },
  },
})
```

The `agent` field sets the default agent. You can override it per-command with `:CodeCompanionCLI agent=<name>`.

### Agent Options

| Option | Type | Description |
|---|---|---|
| `cmd` | `string` | The command to run (e.g. `"claude"`, `"codex"`) |
| `args` | `table` | Arguments to pass to the command |
| `description` | `string` | Description shown in the action palette |
| `provider` | `string` | Which provider to use (defaults to `"terminal"`) |

### Multiple Agents

You can define multiple agents and switch between them:

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

Then use `:CodeCompanionCLI agent=codex <prompt>` to use a specific agent.

## Providers

Providers determine how the CLI agent is run. The built-in `terminal` provider uses a Neovim terminal buffer with `jobstart()`:

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

You can create custom providers and reference them by module path or file path:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      providers = {
        my_provider = {
          -- Can be a codecompanion module, a Lua module, or a file path
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

If an agent's `provider` field doesn't match any entry in the `providers` table, the `terminal` provider is used as a fallback.

## Keymaps

The CLI buffer supports keymaps for navigating between interactions:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      keymaps = {
        next_chat = {
          modes = { n = "}" },
          callback = "keymaps.next_chat",
          description = "[Nav] Next interaction",
        },
        previous_chat = {
          modes = { n = "{" },
          callback = "keymaps.previous_chat",
          description = "[Nav] Previous interaction",
        },
      },
    },
  },
})
```
