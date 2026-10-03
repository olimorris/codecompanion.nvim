---
description: "Use Claude Code, Codex and other agents in a CodeCompanion chat buffer via the Agent Client Protocol, including choosing a default model and mode."
---

# Coding with an Agent

An agent such as Claude Code or Codex brings its own tools, permissions and slash commands, but normally lives in a separate terminal. CodeCompanion runs the agent over the [Agent Client Protocol](/agent-client-protocol) (ACP), so the conversation, its permission requests and its edits all happen in a chat buffer. This guide uses Claude Code throughout. The steps are the same for any other agent once it's installed.

## Installing Claude Code

1. [Install Claude Code](https://docs.anthropic.com/en/docs/claude-code/quickstart)
2. Install [claude-agent-acp](https://github.com/zed-industries/claude-agent-acp), which lets CodeCompanion talk to Claude Code:

```
npm install -g @zed-industries/claude-agent-acp
```

3. Authenticate with your Claude subscription or an API key:

::: code-group

```lua [Subscription]
-- Run `claude setup-token` in your terminal to get the token
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        claude_code = {
          env = {
            CLAUDE_CODE_OAUTH_TOKEN = "cmd:op read op://personal/Claude/token --no-newline",
          },
        },
      },
    },
  },
})
```

```lua [API Key]
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        claude_code = {
          env = {
            ANTHROPIC_API_KEY = "cmd:op read op://personal/Anthropic/credential --no-newline",
          },
        },
      },
    },
  },
})
```

:::

If `CLAUDE_CODE_OAUTH_TOKEN` is already exported in your shell, you can skip step 3. See [Setup: Claude Code](/configuration/adapters-acp#setup-claude-code) for screenshots of the token flow, and [environment variables](/configuration/adapters-http#environment-variables) for other ways to supply a secret.

For other agents, follow their setup section instead: [Codex](/configuration/adapters-acp#setup-codex), [Gemini CLI](/configuration/adapters-acp#setup-gemini-cli), [OpenCode](/configuration/adapters-acp#setup-opencode), [Copilot CLI](/configuration/adapters-acp#setup-copilot-cli) and [others](/configuration/adapters-acp).

## Making It the Chat Adapter

To use Claude Code for every chat:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "claude_code", -- Or "codex", "gemini_cli", "opencode", "copilot_acp"...
    },
  },
})
```

To try it without changing your config, run:

```
:CodeCompanionChat adapter=claude_code
```

The agent takes a few seconds to start. Once it's connected, you talk to it like any other chat, and send with `<C-s>` or `<CR>`.

## Choosing a Default Model and Mode

When a session starts, the agent tells CodeCompanion which _session config options_ it has, such as the model, the mode and the reasoning level. Every chat starts on the agent's own defaults unless you set your own.

The model can be set alongside the adapter:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "claude_code",
        model = "opus",
      },
    },
  },
})
```

The mode, and every other option, goes in the adapter's `defaults.session_config_options`:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        claude_code = {
          defaults = {
            session_config_options = {
              model = "opus",
              mode = "acceptEdits",
            },
          },
        },
      },
    },
  },
  interactions = {
    chat = {
      adapter = "claude_code",
    },
  },
})
```

Each key is an option's category (`model`, `mode`, `thought_level`) and each value is matched against the agent's values or their display names, ignoring case. The model is always set first, as some agents change their other options depending on the model. If a value doesn't match, CodeCompanion logs a warning and the chat stays on the agent's default.

To see which options and values your agent offers, press `gd` in a chat buffer to open the [debug window](/usage/chat-buffer/#debug-window), or run `/acp_session_options`.

> [!NOTE]
> If you set the model in both places, `session_config_options` takes precedence

## Changing Model and Mode Mid-Chat

| Keymap / Command | Action |
|---|---|
| `ga` | Change adapter, then pick a model from the agent's list |
| `/acp_session_options` | Change any session config option, such as the mode or reasoning level |
| `/command` | Restart the agent with a different command from the adapter's `commands`, such as Claude Code's `yolo`. This starts a new conversation with the agent |

The current model and option values are marked with `*`.

## Permissions

The agent decides when it needs your permission, and CodeCompanion shows the request in the chat buffer. Only the options the agent offers are listed:

| Keymap | Action |
|---|---|
| `gv` | View the proposed edit in a floating diff |
| `g1` | Always accept. The agent remembers this, not CodeCompanion |
| `g2` | Accept this time |
| `g3` | Reject |
| `g4` | Cancel the request |

A proposed edit of six lines or fewer is shown in the chat buffer. A larger one opens in a floating diff if the chat buffer is visible, where the same keymaps apply and `}` and `{` move between hunks. See [Diff](/configuration/diff) to change the threshold.

<img src="https://github.com/user-attachments/assets/ddf38a59-0e82-400b-8801-2296ed19d39f" alt="Claude Code permission request" />

Your chat's [approval mode](/usage/chat-buffer/agents-tools#approval-modes) also applies to the agent. Press `gty` to choose one:

- **Ask** - Every request is shown to you
- **Auto** - Reads, searches, fetches, edits and safe shell commands are accepted for you. Everything else is shown to you
- **YOLO** - Every request is accepted for you

A request accepted by a mode is only ever accepted once, so the agent doesn't keep the permission after you leave that mode. See [Controlling Tool Approvals](/guides/tool-approvals) for what counts as a safe command.

## Using the Agent's Slash Commands

The agent's own slash commands are triggered with `\`, which keeps them apart from CodeCompanion's `/` [slash commands](/usage/chat-buffer/slash-commands):

```md
\compact
```

CodeCompanion changes `\compact` to `/compact` before sending it. Commands are discovered from the agent, so they appear in completion one to five seconds after the chat opens. Not every command the agent has in its terminal is available over ACP.

## Sharing Context

[Editor context](/usage/chat-buffer/editor-context) and CodeCompanion's slash commands work as they do with any other adapter:

```md
Why does #{buffer} fail on the errors in #{diagnostics}?
```

**A buffer or file is shared as its path, and the agent reads it from disk, so save your changes first.** Everything else, such as `#{selection}`, `#{diagnostics}` and `#{terminal}`, is sent as text. An image added with `/file` is sent as an image to agents that accept them, which includes Claude Code.

## Passing MCP Servers to the Agent

To give the agent the [MCP servers](/configuration/mcp) you've configured for CodeCompanion, or a separate list of its own:

::: code-group

```lua [Inherit]
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        claude_code = {
          defaults = {
            mcpServers = "inherit_from_config",
          },
        },
      },
    },
  },
  mcp = {
    servers = {
      ["sequential-thinking"] = {
        cmd = { "npx", "-y", "@modelcontextprotocol/server-sequential-thinking" },
      },
    },
    opts = {
      default_servers = { "sequential-thinking" },
    },
  },
})
```

```lua [Manual]
require("codecompanion").setup({
  adapters = {
    acp = {
      extend = {
        claude_code = {
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
        },
      },
    },
  },
})
```

:::

With `inherit_from_config`, only the servers in `mcp.opts.default_servers` are passed. The agent starts and runs them itself, so they don't appear in the chat buffer's context. See [Configuring MCP Servers](/configuration/adapters-acp#configuring-mcp-servers) for more.

## Reviewing the Agent's Work

Once the agent has finished, run:

```
:CodeCompanionCodeReview
```

This shows every change made since your first message, and lets you accept, revert or comment on each hunk. Send your comments back with `#{code_review}` in your next message. See [Reviewing an Agent's Changes](/guides/reviewing-changes) for the full workflow.

## ACP or the CLI Interaction

`:CodeCompanionCLI` runs the agent's own terminal interface inside Neovim, rather than a chat buffer. See [CLI](/usage/cli) to set it up.

| | ACP | CLI |
|---|---|---|
| Where you talk to the agent | A chat buffer | The agent's own interface, in a Neovim terminal |
| Permission requests | In the chat buffer, with CodeCompanion's approval modes | In the agent's interface |
| Agent features | Only what the agent exposes over ACP | Everything the agent has |
| Switching agent or model | `ga` in the same chat | Start another CLI interaction |
| Sharing context | Editor context and slash commands in the prompt | Editor context sent from any buffer with `require("codecompanion").cli()` |

Choose ACP if you want to read, search and yank the conversation like any other buffer. Choose the CLI if you rely on a feature the agent doesn't expose over ACP, such as its plan view or a particular slash command.

## Limitations

- Agents only work in the chat buffer, not in the [inline](/usage/inline) interaction or for background tasks
- CodeCompanion's own tools, such as `@{files}` and `@{agent}`, aren't offered to an agent. It uses its own
- CodeCompanion's system prompt isn't sent to the agent
- CodeCompanion doesn't [compact](/configuration/context-management) an agent's conversation. The agent manages its own context, and `\compact` asks it to
- `/save` and `/rename` aren't available. The agent keeps its own sessions, which `/resume` lists in a new chat if the agent supports it
- An agent's plan isn't shown in the chat buffer, and agents can't use a Neovim terminal. See [ACP Support](/agent-client-protocol#current-limitations)
