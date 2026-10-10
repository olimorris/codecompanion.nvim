---
description: "Connect MCP servers to CodeCompanion, choose which start with every chat and override the behaviour of their tools."
---

# Configuring MCP Servers

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io) is an open standard for connecting LLMs to external systems. CodeCompanion starts the MCP servers you configure and adds their tools to the [chat buffer](/usage/chat-buffer/). The parts of the protocol it implements are listed on the [MCP](/model-context-protocol) page.

## Servers

Servers are defined in `mcp.servers`, keyed by name:

::: code-group

```lua [Basic]
require("codecompanion").setup({
  mcp = {
    servers = {
      ["tavily-mcp"] = {
        cmd = { "npx", "-y", "tavily-mcp@latest" },
      },
    },
  },
})
```

```lua [Environment Variables]
require("codecompanion").setup({
  mcp = {
    servers = {
      ["tavily-mcp"] = {
        cmd = { "npx", "-y", "tavily-mcp@latest" },
        env = {
          TAVILY_API_KEY = "cmd:op read op://personal/Tavily_API/credential --no-newline",
        },
      },
    },
  },
})
```

```lua [Deferred]
require("codecompanion").setup({
  mcp = {
    servers = {
      ["tavily-mcp"] = function()
        return {
          cmd = { "npx", "-y", "tavily-mcp@latest" },
          env = {
            TAVILY_API_KEY = os.getenv("TAVILY_API_KEY"),
          },
        }
      end,
    },
  },
})
```

:::

`env` values are resolved like an adapter's [environment variables](/configuration/adapters-http#environment-variables), so the example above reads the key with the [1Password CLI](https://developer.1password.com/docs/cli/). A server defined as a function is only called the first time the server is needed.

### Roots

[Roots](https://modelcontextprotocol.io/specification/2025-11-25/client/roots) tell a server which directories it may access. They're off unless you add `roots` to a server:

::: code-group

```lua [Roots]
require("codecompanion").setup({
  mcp = {
    servers = {
      filesystem = {
        cmd = { "npx", "-y", "@modelcontextprotocol/server-filesystem" },
        roots = function()
          -- Return a list of roots, as per:
          -- https://modelcontextprotocol.io/specification/2025-11-25/client/roots#listing-roots
        end,
      },
    },
  },
})
```

```lua [Root List Changes]
require("codecompanion").setup({
  mcp = {
    servers = {
      filesystem = {
        cmd = { "npx", "-y", "@modelcontextprotocol/server-filesystem" },
        ---@param notify fun()
        register_roots_list_changed = function(notify)
          -- Call `notify()` whenever the list of roots changes
        end,
      },
    },
  },
})
```

:::

> [!IMPORTANT]
> Roots are a hint. A compliant server respects them, but CodeCompanion can't enforce them, so run untrusted servers in a container

### Server Instructions

A server can send instructions on how to use its tools. To replace them, set `server_instructions` to a string, or to a function that receives the server's own instructions and returns a string:

```lua
require("codecompanion").setup({
  mcp = {
    servers = {
      ["tavily-mcp"] = {
        cmd = { "npx", "-y", "tavily-mcp@latest" },
        server_instructions = function(instructions)
          return instructions .. "\n\nPrefer official documentation over blog posts."
        end,
      },
    },
  },
})
```

## Default Servers

Servers in `default_servers` start with the first chat buffer, and their tools are added to every new chat buffer. Start any other server with the [/mcp](/usage/chat-buffer/slash-commands#mcp) slash command:

```lua
require("codecompanion").setup({
  mcp = {
    servers = {
      ["sequential-thinking"] = {
        cmd = { "npx", "-y", "@modelcontextprotocol/server-sequential-thinking" },
      },
      ["tavily-mcp"] = {
        cmd = { "npx", "-y", "tavily-mcp@latest" },
      },
    },
    opts = {
      default_servers = { "sequential-thinking" },
    },
  },
})
```

A [prompt library](/configuration/prompt-library) item that sets `mcp_servers` uses those servers instead, and `mcp_servers = "none"` starts none.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `default_servers` | `{}` | Servers to start and add to every chat buffer |
| `acp_enabled` | `true` | Allow ACP adapters to use your default servers |
| `timeout` | `30000` | Milliseconds to wait for a server to respond |

ACP agents run their own tools, so CodeCompanion doesn't add MCP tools to an ACP chat. Instead, the agent can connect to your default servers itself. See [Configuring MCP Servers](/configuration/adapters-acp#configuring-mcp-servers) for ACP adapters.

## Overriding Tool Behaviour

A server can expose many tools. A _math_ server might provide `add`, `subtract`, `multiply` and `divide`. `tool_overrides` changes them one at a time, keyed by the tool's name on the MCP server, not the prefixed name CodeCompanion gives it:

::: code-group

```lua [Requiring Approval]
require("codecompanion").setup({
  mcp = {
    servers = {
      ["math-server"] = {
        cmd = { "npx", "-y", "math-mcp-server" },
        tool_overrides = {
          divide = {
            opts = {
              require_approval_before = true,
            },
          },
        },
      },
    },
  },
})
```

```lua [Custom Output]
require("codecompanion").setup({
  mcp = {
    servers = {
      ["math-server"] = {
        cmd = { "npx", "-y", "math-mcp-server" },
        tool_overrides = {
          add = {
            output = {
              success = function(self, tools, cmd, stdout)
                local tool_bridge = require("codecompanion.mcp.tool_bridge")
                local content = stdout and stdout[#stdout]
                local output = tool_bridge.format_tool_result_content(content)
                local msg = string.format("%d + %d = %s", self.args.a, self.args.b, output)
                tools.chat:add_tool_output({ tool = self, for_llm = output, for_user = msg })
              end,
            },
          },
        },
      },
    },
  },
})
```

```lua [System Prompt]
require("codecompanion").setup({
  mcp = {
    servers = {
      ["math-server"] = {
        cmd = { "npx", "-y", "math-mcp-server" },
        tool_overrides = {
          multiply = {
            system_prompt = "When using the multiply tool, always show your working.",
          },
        },
      },
    },
  },
})
```

:::

Each override can set:

| Option | Type | Description |
| --- | --- | --- |
| `enabled` | `boolean` | Whether the tool is available |
| `opts` | `table` | Tool options, such as `require_approval_before` |
| `output` | `table` | Output handlers: `success`, `error`, `prompt`, `rejected` and `cancelled` |
| `system_prompt` | `string` | Extra system prompt for the tool |
| `timeout` | `number` | Milliseconds to wait for the tool |

> [!WARNING]
> MCP tools run without asking unless you set `require_approval_before`

### Tool Defaults

`tool_defaults` sets options for every tool on a server. `tool_overrides` takes precedence:

```lua
require("codecompanion").setup({
  mcp = {
    servers = {
      ["math-server"] = {
        cmd = { "npx", "-y", "math-mcp-server" },
        tool_defaults = {
          require_approval_before = true,
        },
        tool_overrides = {
          add = {
            opts = {
              require_approval_before = false,
            },
          },
        },
      },
    },
  },
})
```
