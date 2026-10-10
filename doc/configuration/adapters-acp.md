---
description: "Connect CodeCompanion to agents such as Claude Code, Codex and Gemini CLI over the Agent Client Protocol."
---

# Configuring ACP Adapters

ACP adapters connect CodeCompanion to an agent, such as Claude Code or Codex, over the [Agent Client Protocol](https://agentclientprotocol.com). CodeCompanion starts the agent as a separate process, and the agent brings its own tools, approvals and context management. ACP adapters sit under `adapters.acp` and share most of their configuration with [HTTP adapters](/configuration/adapters-http), so read the two pages together.

## Built-in Adapters

| Adapter | Agent | Command |
| --- | --- | --- |
| `auggie_cli` | [Auggie CLI](#setup-auggie-cli-from-augment-code) | `auggie --acp` |
| `cagent` | [Cagent](#setup-cagent) | `cagent acp basic_agent.yaml` |
| `claude_code` | [Claude Code](#setup-claude-code) | `claude-agent-acp` |
| `cline_cli` | [Cline CLI](#setup-cline-cli) | `cline --acp` |
| `codex` | [Codex](#setup-codex) | `codex-acp` |
| `copilot_acp` | [Copilot CLI](#setup-copilot-cli) | `copilot --acp --stdio` |
| `cursor_cli` | [Cursor CLI](#setup-cursor-cli) | `agent acp` |
| `gemini_cli` | [Gemini CLI](#setup-gemini-cli) | `gemini --experimental-acp` |
| `goose` | [Goose](#setup-goose-cli) | `goose acp` |
| `kilocode` | [Kilo Code](#setup-kilo-code) | `kilo acp` |
| `kimi_cli` | [Kimi CLI](#setup-kimi-cli) | `kimi acp` |
| `kiro` | [Kiro CLI](#setup-kiro-cli) | `kiro-cli acp` |
| `mistral_vibe` | [Mistral Vibe](#setup-mistral-vibe) | `vibe-acp` |
| `opencode` | [OpenCode](#setup-opencode) | `opencode acp` |

The command must be on your `PATH`.

## Customising an Adapter

There are two ways to customise a built-in adapter, and this page uses both:

- **Function** - For full or computed setups, such as custom `commands` or `defaults`, or values resolved when the adapter loads
- **`extend` table** - For static overrides, such as credentials or a default value

::: code-group

```lua [Function]
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          commands = {
            default = { "some-other-gemini", "--experimental-acp" },
          },
          defaults = {
            auth_method = "gemini-api-key",
            timeout = 20000, -- milliseconds
          },
          env = { GEMINI_API_KEY = "cmd:op read op://personal/Gemini/credential --no-newline" },
        })
      end,
    },
  },
})
```

```lua [Extend Table]
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        gemini_cli = {
          defaults = { auth_method = "gemini-api-key" },
          env = { GEMINI_API_KEY = "cmd:op read op://personal/Gemini/credential --no-newline" },
        },
      },
    },
  },
})
```

:::

> [!IMPORTANT]
> Each key in `extend` is the adapter's key under `adapters.acp`, not the adapter's `name`

Values in `env` are resolved in the same way as for [HTTP adapters](/configuration/adapters-http#environment-variables), then passed to the agent's process as environment variables.

The `auth_method` must match an ID the agent advertises. If it doesn't, the log lists the ones that are available.

## Setting a Default Adapter

To use an agent for every chat:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "gemini_cli",
    },
  },
})
```

## Commands

An adapter starts its agent with the `default` entry in its `commands` table. `claude_code` and `gemini_cli` also have a `yolo` command, which starts the agent with `--yolo`. To add your own:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        cagent = {
          commands = {
            reviewer = { "cagent", "acp", "reviewer.yaml" },
          },
        },
      },
    },
  },
})
```

To start a chat with a command other than `default`:

```
:CodeCompanionChat adapter=cagent command=reviewer
```

From inside a chat buffer, use the [/command](/usage/chat-buffer/slash-commands#command) slash command.

## Setting Default Session Config Options

[Session config options](https://agentclientprotocol.com/protocol/session-config-options) are settings an agent shares at the start of a session, such as its models, modes and reasoning levels. Set their defaults in `defaults.session_config_options`, keyed by the option's category.

### Models

Set the model on the interaction, or on the adapter so it applies everywhere:

::: code-group

```lua [Interactions] {4-7}
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "codex",
        model = "gpt-5.4",
      },
    },
  },
})
```

```lua [Adapter String] {6-10}
require("codecompanion").setup({
  adapters = {
    acp = {
      codex = function()
        return require("codecompanion.adapters").extend("codex", {
          defaults = {
            session_config_options = {
              model = "gpt-5.4",
            },
          },
        })
      end,
    },
  },
})
```

```lua [Adapter Function] {6-14}
require("codecompanion").setup({
  adapters = {
    acp = {
      codex = function()
        return require("codecompanion.adapters").extend("codex", {
          defaults = {
            session_config_options = {
              ---@param self CodeCompanion.ACPAdapter
              ---@return string
              model = function(self)
                return "gpt-5.4"
              end,
            },
          },
        })
      end,
    },
  },
})
```

:::

### Others

Any other option goes in the same table:

```lua {6-11}
require("codecompanion").setup({
  adapters = {
    acp = {
      codex = function()
        return require("codecompanion.adapters").extend("codex", {
          defaults = {
            session_config_options = {
              mode = "Full Access",
              thought_level = "Xhigh",
            },
          },
        })
      end,
    },
  },
})
```

A value matches either the option's value or its name, ignoring case. The model is set first, as it can change which other options are available. To see an agent's options and their values, open the [debug window](/usage/chat-buffer/#debug-window).

## Configuring MCP Servers

Some agents [support](https://agentclientprotocol.com/protocol/session-setup#mcp-servers) connecting to Model Context Protocol (MCP) servers. To pass on the servers in your [MCP configuration](/configuration/mcp):

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          defaults = {
            mcpServers = "inherit_from_config",
          },
        })
      end,
    },
  },
})
```

Only the servers in `mcp.opts.default_servers` are passed, and setting `mcp.opts.acp_enabled = false` stops them being passed at all. The agent starts and runs the servers itself, so they don't appear in the chat buffer's context.

To set the servers on the adapter instead, such as Claude Code with the [sequential-thinking](https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking) server over stdio:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          defaults = {
            mcpServers = {
              {
                name = "sequential-thinking",
                command = "npx",
                args = { "-y", "@modelcontextprotocol/server-sequential-thinking" },
                env = {},
              },
            },
          },
        })
      end,
    },
  },
})
```

## Hiding Preset Adapters

To list only the adapters in your own config, leaving out the built-in ones:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      opts = {
        show_presets = false,
      },
    },
  },
})
```

To hide individual adapters, see [Hiding Adapters](/configuration/adapters-http#hiding-adapters).

## Setup: Auggie CLI from Augment Code

Follow the [Getting Started](https://docs.augmentcode.com/cli/overview#getting-started) guide for [Auggie CLI](https://docs.augmentcode.com/cli/overview), then select the `auggie_cli` adapter.

## Setup: Cagent

To use Docker's [Cagent](https://github.com/docker/cagent):

1. [Install](https://github.com/docker/cagent?tab=readme-ov-file#installation) Cagent
2. [Create an agent](https://github.com/docker/cagent?tab=readme-ov-file#run-agents) in your repository
3. Test it with `cagent run your_agent.yaml`
4. Point the `cagent` adapter at your agent:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      cagent = function()
        return require("codecompanion.adapters").extend("cagent", {
          commands = {
            default = {
              "cagent",
              "acp",
              "your_agent.yaml",
            },
          },
        })
      end,
    },
  },
})
```

For more than one agent, add a [command](#commands) for each.

## Setup: Claude Code

To use [Claude Code](https://www.anthropic.com/claude-code):

1. [Install](https://docs.anthropic.com/en/docs/claude-code/quickstart#step-1%3A-install-claude-code) Claude Code
2. [Install](https://github.com/zed-industries/claude-agent-acp) Zed's ACP adapter for Claude Code
3. Authenticate with a Claude Pro subscription or an API key, as below

### Using Claude Pro Subscription

1. Run `claude setup-token` and authorise in the browser:
<img src="https://github.com/user-attachments/assets/28b70ba1-6fd2-4431-9905-c60c83286e4c" alt="Claude Pro Authorization" />
2. Copy the OAuth token, shown in yellow:
<img src="https://github.com/user-attachments/assets/73992480-20a6-4858-a9fe-93a4e49004ff" alt="Claude Pro OAuth Token" />
3. Set it on the `claude_code` adapter:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          env = {
            CLAUDE_CODE_OAUTH_TOKEN = "my-oauth-token",
          },
        })
      end,
    },
  },
})
```

If `CLAUDE_CODE_OAUTH_TOKEN` is already exported in your shell, skip step 3. See [environment variables](/configuration/adapters-http#environment-variables) for other ways to supply the token.

### Using an API Key

1. [Create](https://console.anthropic.com/settings/keys) an API key in the Anthropic console
2. Set it on the `claude_code` adapter:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          env = {
            ANTHROPIC_API_KEY = "my-api-key",
          },
        })
      end,
    },
  },
})
```

## Setup: Cline CLI

To use [Cline CLI](https://cline.bot/cli):

1. [Install](https://docs.cline.bot/getting-started/installing-cline#cli) Cline CLI
2. Run `cline auth`
3. Select the `cline_cli` adapter

## Setup: Codex

To use OpenAI's [Codex](https://openai.com/codex/), install [codex-acp](https://github.com/agentclientprotocol/codex-acp).

The adapter authenticates with `OPENAI_API_KEY` from your shell by default. To set the key on the adapter, or to sign in with ChatGPT instead:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      codex = function()
        return require("codecompanion.adapters").extend("codex", {
          defaults = {
            auth_method = "api-key", -- Can be "api-key" or "chat-gpt"
          },
          env = {
            OPENAI_API_KEY = "my-api-key",
          },
        })
      end,
    },
  },
})
```

## Setup: Copilot CLI

[Install](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) Copilot CLI, run `copilot` to sign in, then select the `copilot_acp` adapter.

## Setup: Cursor CLI

To use [Cursor](https://www.cursor.com/):

1. Install `agent` from the [Cursor CLI documentation](https://cursor.com/docs/cli/overview)
2. Run `agent login`
3. Select the `cursor_cli` adapter

## Setup: Gemini CLI

Install [Gemini CLI](https://github.com/google-gemini/gemini-cli), then choose an `auth_method`:

| Method | Description |
| --- | --- |
| `oauth-personal` | Sign in with your Google account (default) |
| `gemini-api-key` | Use `GEMINI_API_KEY` |
| `vertex-ai` | Use Vertex AI |

To use an API key from the [1Password CLI](https://developer.1password.com/docs/cli/get-started/):

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          defaults = {
            auth_method = "gemini-api-key",
          },
          env = {
            GEMINI_API_KEY = "cmd:op read op://personal/Gemini_API/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

## Setup: Goose CLI

[Install](https://goose-docs.ai/docs/getting-started/installation/) and set up [Goose](https://goose-docs.ai/) CLI, then select the `goose` adapter.

## Setup: Kilo Code

[Install](https://kilo.ai/docs/getting-started/installing#cli) and [configure](https://kilo.ai/docs/getting-started/setup-authentication#cli) [Kilo Code](https://kilo.ai), then select the `kilocode` adapter.

To set the model, edit `~/.config/kilo/kilo.json`:

```json
{
  "$schema": "https://kilo.ai/config.json",
  "model": "kilo/kilo-auto/free"
}
```

## Setup: Kimi CLI

[Install](https://github.com/MoonshotAI/kimi-cli?tab=readme-ov-file#installation) Kimi CLI, run `kimi` and then `/login` to set your API key, then select the `kimi_cli` adapter.

## Setup: Kiro CLI

[Install](https://kiro.dev/docs/cli/) Kiro CLI and sign in, then select the `kiro` adapter.

## Setup: Mistral Vibe

[Install](https://github.com/mistralai/mistral-vibe) [Mistral Vibe](https://github.com/mistralai/mistral-vibe), run `vibe --setup` to set your API key, then select the `mistral_vibe` adapter.

## Setup: OpenCode

[Install](https://opencode.ai/docs/#install) and [configure](https://opencode.ai/docs/#configure) [OpenCode](https://opencode.ai), then select the `opencode` adapter.

To set the model, edit `~/.config/opencode/opencode.jsonc` or `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "github-copilot/claude-sonnet-4.5"
}
```

OpenCode doesn't send diffs for [code review](/usage/code-review) by default. To turn them on, [set its permissions](https://opencode.ai/docs/permissions/) to ask:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode-go/mimo-v2.5-pro",
  "permission": {
    "*": "ask"
  }
}
```

## Creating Custom ACP Adapters

For an agent without a built-in adapter, define your own. This example uses a hypothetical `myagent` CLI, and the [built-in ACP adapters](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/acp) make a good reference:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      my_agent = function()
        local helpers = require("codecompanion.adapters.acp.helpers")
        return {
          name = "my_agent",
          formatted_name = "MyAgent",
          type = "acp",
          roles = {
            llm = "assistant",
            user = "user",
          },
          commands = {
            default = {
              "myagent",
              "--acp",
            },
          },
          defaults = {
            mcpServers = {},
            timeout = 20000, -- milliseconds
          },
          parameters = {
            protocolVersion = 1,
            clientCapabilities = {
              fs = { readTextFile = true, writeTextFile = true },
            },
            clientInfo = {
              name = "CodeCompanion.nvim",
              version = "1.0.0",
            },
          },
          handlers = {
            lifecycle = {
              setup = function(self)
                return true
              end,
              auth = function(self)
                return true
              end,
            },
            request = {
              build_messages = helpers.build_messages,
            },
          },
        }
      end,
    },
  },
})
```

Raise issues and questions about user-created adapters in the [adapter discussions](https://github.com/olimorris/codecompanion.nvim/discussions?discussions_q=is%3Aopen+label%3A%22tip%3A+adapter%22).

<style scoped>
table td:first-child code {
  white-space: nowrap;
}
</style>
