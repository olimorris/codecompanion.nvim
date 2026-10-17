---
description: "Check which parts of the Model Context Protocol (MCP) CodeCompanion implements, and how MCP servers reach the chat buffer."
---

# Model Context Protocol (MCP)

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io) is an open standard for connecting LLMs to external systems. CodeCompanion implements the parts of it that help you code: running servers and using their tools and prompts.

## Usage

[Default servers](/configuration/mcp#default-servers) start when you open your first chat buffer, and their tools are added to it. Start or stop any server with the [/mcp](/usage/chat-buffer/slash-commands#mcp) slash command.

Once a server is running, its [tools](/usage/chat-buffer/agents-tools#mcp) are available in the chat buffer, and its prompts can be added with the [/mcp-prompts](/usage/chat-buffer/slash-commands#mcp-prompts) slash command.

ACP agents don't use CodeCompanion's MCP client. Instead, your servers can be [passed to the agent](/configuration/adapters-acp#configuring-mcp-servers).

## Implementation

| Feature | Supported | Details |
|---|---|---|
| Transport: Stdio | ✅ | |
| Transport: Streamable HTTP | ❌ | |
| Basic: Cancellation | ✅ | On timeout, or when you cancel |
| Basic: Progress | ❌ | |
| Basic: Task | ❌ | |
| Client: Roots | ✅ | Disabled by default |
| Client: Sampling | ❌ | |
| Client: Elicitation | ❌ | |
| Server: Completion | ❌ | |
| Server: Pagination | ✅ | |
| Server: Prompts | ✅ | Text content from user messages only |
| Server: Resources | ❌ | |
| Server: Tools | ✅ | Text content only |
| Server: Tool list changed notification | ❌ | |

## Protocol Version

CodeCompanion implements MCP version **2025-11-25**.

## See Also

- [Model Context Protocol Specification](https://modelcontextprotocol.io/specification/2025-11-25) - The official MCP documentation
- [Configuring MCP Servers](/configuration/mcp) - Adding servers and overriding their tools
