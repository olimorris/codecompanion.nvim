---
description: How to leverage Model Context Protocol (MCP) servers within CodeCompanion.nvim
---

# Model Context Protocol (MCP) Support

CodeCompanion implements the [Model Context Protocol (MCP)](https://modelcontextprotocol.io) to enable you to connect the plugin to external systems and applications. The plugin only implements a subset of the full MCP specification, focusing on the features that enable developers to enhance their coding experience.

## Usage

To use MCP servers within CodeCompanion, refer to the [tools](/usage/chat-buffer/tools#mcp) section in the chat buffer usage section of the documentation.

If [enabled](/configuration/mcp#enabling-servers), the servers will be started when you open a chat buffer for the first time. However, you can use the [MCP slash command](/usage/chat-buffer/slash-commands#mcp) to start or stop servers manually.

## Implementation


| Feature Category                       | Supported | Details                                                     |
|----------------------------------------|-----------|-------------------------------------------------------------|
| Transport: Stdio                       | ✅        |                                                             |
| Transport: Streamable HTTP             | ❌        |                                |
| Basic: Cancellation                    | ✅        | Timeout and user can cancel manually                        |
| Basic: Progress                        | ❌        |                                |
| Basic: Task                            | ❌        | |
| Client: Roots                          | ✅        | Disabled by default                                         |
| Client: Sampling                       | ❌        | |
| Client: Elicitation                    | ❌        | |
| Server: Completion                     | ❌        | |
| Server: Pagination                     | ✅        |                                                             |
| Server: Prompts                        | ❌        | |
| Server: Resources                      | ❌        | |
| Server: Tools                          | ✅        | Currently only supports Text Content                        |
| Server: Tool list changed notification | ❌        | |


## Protocol Version

CodeCompanion currently supports MCP version **2025-11-25**.

## See Also

- [Model Context Protocol Specification](https://modelcontextprotocol.io/specification/2025-11-25) - Official MCP documentation
