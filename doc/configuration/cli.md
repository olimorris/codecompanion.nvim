---
description: "Configure CLI agents in CodeCompanion — define agents like Claude Code or Codex, set custom commands, configure the terminal provider, and manage input settings."
---

# Configuring the Command-Line Interface (CLI)

By default, CodeCompanion uses the _terminal_ provider for CLI interactions, which runs agents in a Neovim terminal buffer. However, the CLI system is flexible and allows you to define custom agents and providers to suit your workflow.

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

## Hooks

CLI interactions can integrate with agents that support hooks, enabling the CodeCompanion event system to react to the agent in realtime. Without this, features that need to know where a turn starts and ends, such as the [code review](/usage/code-review), are limited.

CodeCompanion sets `CODECOMPANION_CLI_BUFNR` in the agent's environment, and Neovim sets `$NVIM` to its own server address, so a hook can call back into the session that started it.

### Claude Code

To integrate [Claude Code](https://code.claude.com/docs/en/hooks), add this to `.claude/settings.json`

````json [.claude/settings.json]
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"$CODECOMPANION_CLI_BUFNR\" ] || nvim --server \"$NVIM\" --remote-expr \"v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': 'blocked', 'message': 'Waiting for you'})\" || true"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"$CODECOMPANION_CLI_BUFNR\" ] || nvim --server \"$NVIM\" --remote-expr \"v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': 'blocked', 'message': 'Permission needed'})\" || true"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"$CODECOMPANION_CLI_BUFNR\" ] || nvim --server \"$NVIM\" --remote-expr \"v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': 'working'})\" || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"$CODECOMPANION_CLI_BUFNR\" ] || nvim --server \"$NVIM\" --remote-expr \"v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': 'done'})\" || true"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"$CODECOMPANION_CLI_BUFNR\" ] || nvim --server \"$NVIM\" --remote-expr \"v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': 'submitted'})\" || true"
          }
        ]
      }
    ]
  }
}
````

| Claude Code hook | `event` | CodeCompanion event |
|---|---|---|
| `Notification` | `blocked` | `CodeCompanionCLIBlocked` |
| `PermissionRequest` | `blocked` | `CodeCompanionCLIBlocked` |
| `PostToolUse` | `working` | `CodeCompanionCLIWorking` |
| `Stop` | `done` | `CodeCompanionCLIDone`, plus `CodeCompanionRequestFinished` |
| `UserPromptSubmit` | `submitted` | `CodeCompanionCLISubmitted`, plus `CodeCompanionRequestStarted` |

`UserPromptSubmit` and `Stop` are the pair that marks out a turn. The rest are optional and separate _the agent is thinking_ from _the agent is waiting on you_, which is what a statusline or [herdr](https://herdr.dev) needs to show you that a pane wants attention. `PostToolUse` is what returns the agent to working once you've answered, so take it if you take `Notification` or `PermissionRequest`. It runs on every tool call, which costs a process spawn each time.

`message` is free text and reaches listeners on the event's data payload.

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


## Options

There are a number of options available for CLI interactions:

```lua
require("codecompanion").setup({
  interactions = {
    cli = {
      opts = {
        auto_insert = true, -- Enter insert mode when focusing the CLI terminal
        reload = true, -- Reload buffers when an agent modifies files on disk
      },
    },
  },
})
```

| Option | Type | Default | Description |
|---|---|---|---|
| `auto_insert` | `boolean` | `true` | Automatically enter insert mode when the CLI terminal is focused |
| `reload` | `boolean` | `true` | Watches the cwd for file changes and runs `:checktime` to reload buffers |


## User Interface (UI)

The CLI window inherits its layout from `display.chat.window` by default. You can override specific options via `display.cli.window`:

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

Any options set in `display.cli.window` are merged on top of the chat window defaults. This means you only need to specify what you want to change.

You can also pass `width` and `height` overrides via the Lua API:

```lua
require("codecompanion").cli("fix the tests", {
  width = 0.5,
  height = 0.8,
})
```

