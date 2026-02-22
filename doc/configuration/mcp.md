---
description: Learn how to configure MCP servers within CodeCompanion.nvim
---

# Configuring MCP Servers

In [#2549](https://github.com/olimorris/codecompanion.nvim/pull/2549), CodeCompanion added support for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io), an open-source standard for connecting AI applications to external systems.

You can find out which parts of the protocol CodeCompanion has implemented on the [MCP](/model-context-protocol) page. Currently, you can leverage MCP servers with [chat interactions](/usage/chat-buffer/index).

## Configuring MCP Servers

You can give CodeCompanion knowledge of MCP servers via the `mcp.servers` configuration option. This is a list of server definitions, each specifying how to connect to an MCP server

### Basic Configuration

::: code-group

```lua [Basic Example]
require("codecompanion").setup({
  mcp = {
    ["tavily-mcp"] = {
      cmd = { "npx", "-y", "tavily-mcp@latest" },
    },
  },
})
```

```lua [Environment Variables] {5-7}
require("codecompanion").setup({
  mcp = {
    ["tavily-mcp"] = {
      cmd = { "npx", "-y", "tavily-mcp@latest" },
      env = {
        TAVILY_API_KEY = "cmd:op read op://personal/Tavily_API/credential --no-newline",
      },
    },
  },
})
```

:::

In the example above, we're using [1Password CLI](https://developer.1password.com/docs/cli/) tool to fetch the API key. However, you can leverage CodeCompanion's built-in [environment variable](/configuration/adapters-http#environment-variables) capabilities to fetch the value from any source you like.

### Roots

> [!IMPORTANT]
> The `roots` feature is a hint to MCP servers. Compliant servers use it to limit file system access, but CodeCompanion cannot enforce this. For untrusted servers, use isolation mechanisms like containers.

[Roots](https://modelcontextprotocol.io/specification/2025-11-25/client/roots) allow you to specify directories that the MCP server can access. By default, roots are disabled for security reasons. You can enable them by adding a `roots` field to your server configuration:

::: code-group

```lua [Roots]
require("codecompanion").setup({
  mcp = {
    filesystem = {
      cmd = { "npx", "-y", "@modelcontextprotocol/server-filesystem" },
      roots = function()
        -- Return a list of names and directories as per:
        -- https://modelcontextprotocol.io/specification/2025-11-25/client/roots#listing-roots
      end,
    },
  },
})
```

```lua [Root List Changes]
require("codecompanion").setup({
  mcp = {
    filesystem = {
      cmd = { "npx", "-y", "@modelcontextprotocol/server-filesystem" },
      ---@param notify fun()
      register_roots_list_changes = function(notify)
        -- Call `notify()` whenever the list of roots changes.
      end,
    },
  },
})
```

:::

## Starting Servers

By default, all MCP servers are started when a chat buffer is opened for the first time - remaining active until Neovim is closed. This behaviour can be changed by setting `mcp.auto_start = false`. You can also change this at an individual server level:

::: code-group

```lua [Globally] {3}
require("codecompanion").setup({
  mcp = {
    auto_start = false,
    ["tavily-mcp"] = {
      cmd = { "npx", "-y", "tavily-mcp@latest" },
    },
  },
})
```

```lua [Per Server] {3,6-8}
require("codecompanion").setup({
  mcp = {
    auto_start = true,
    ["tavily-mcp"] = {
      cmd = { "npx", "-y", "tavily-mcp@latest" },
      opts = {
        auto_start = false,
      },
    },
  },
})
```

:::

## Adding Tools to Chat Buffers

By default, when `mcp.add_to_chat = true` (the default), all started MCP servers will have their tools automatically added to every new chat buffer. You can disable this globally and opt-in per server with the `add_to_chat` option:

::: code-group

```lua [Per Server] {3-4,8-9,16-17}
require("codecompanion").setup({
  mcp = {
    add_to_chat = false,
    auto_start = true,
    servers = {
      ["sequential-thinking"] = {
        cmd = { "npx", "-y", "@modelcontextprotocol/server-sequential-thinking" },
        opts = {
          add_to_chat = true,
        },
      },
      ["tavily-mcp"] = {
        cmd = { "npx", "-y", "tavily-mcp@latest" },
        opts = {
          add_to_chat = false,
        },
      },
    },
  },
})
```

:::

In the example above, `add_to_chat = false` is set globally, so no server tools are added to chat buffers by default. The `sequential-thinking` server overrides this with `add_to_chat = true`, so its tools will be available in every new chat buffer. The `tavily-mcp` server's tools can still be added on-demand via the `/mcp` slash command.

> [!NOTE]
> If `mcp_servers` are explicitly specified in a prompt library item, those take precedence and the `add_to_chat` logic is skipped for that chat buffer.

## Overriding Tool Behaviour

An MCP server can expose multiple tools. For example, a "math" server might provide `add`, `subtract`, `multiply`, and `divide` tools. You can override the behaviour of individual tools using the `tool_overrides` configuration, allowing you to customise options, output handling, system prompts, and timeouts on a per-tool basis.

The `tool_overrides` field is a table where keys are the **MCP tool names** (not the prefixed names used internally by CodeCompanion):

::: code-group

```lua [Requiring Approval]
require("codecompanion").setup({
  mcp = {
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
})
```

```lua [Custom Output]
require("codecompanion").setup({
  mcp = {
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
              tools.chat:add_tool_output(self, output, msg)
            end,
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
    ["math-server"] = {
      cmd = { "npx", "-y", "math-mcp-server" },
      tool_overrides = {
        multiply = {
          system_prompt = "When using the multiply tool, always show your working.",
        },
      },
    },
  },
})
```

:::

### Tool Defaults

You can set default options for all tools by setting the `tool_defaults` option. However, note that `tool_overrides` take precedence over them:

```lua
require("codecompanion").setup({
  mcp = {
    ["math-server"] = {
      cmd = { "npx", "-y", "math-mcp-server" },
      tool_defaults = {
        require_approval_before = true,
      },
      -- Per-tool overrides take precedence over tool_defaults
      tool_overrides = {
        add = {
          opts = {
            require_approval_before = false,
          },
        },
      },
    },
  },
})
```


### Override Options

Each tool override can include:

| Option | Type | Description |
|--------|------|-------------|
| `opts` | `table` | Tool options like `require_approval_before`, `require_approval_after` |
| `output` | `table` | Custom output handlers (`success`, `error`, `prompt`, `rejected`, `cancelled`) |
| `system_prompt` | `string` | Additional system prompt text for this tool |
| `timeout` | `number` | Custom timeout in milliseconds for this tool |
| `enabled` | `boolean`  | Whether the tool is enabled |


