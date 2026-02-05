---
description: How CodeCompanion implements the Agent Client Protocol (ACP)
---

# Agent Client Protocol (ACP) Support

CodeCompanion implements the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/) to enable you to work with coding agents from within Neovim. ACP is an open standard that enables structured interaction between clients (like CodeCompanion) and AI agents, providing capabilities such as session management, file system operations, tool execution, and permission handling.

This page provides a technical reference for what's supported in CodeCompanion and how it's been implemented.

## Implementation

CodeCompanion provides comprehensive support for the ACP specification:

| Feature Category | Supported | Details |
|------------------|---------------|---------|
| **Core Protocol** | ✅ | JSON-RPC 2.0, streaming responses, message buffering |
| **Authentication** | ✅ | Multiple auth methods, adapter-level hooks |
| **Content Types** | ✅ | Text, images, embedded resources |
| **File System** | ✅ | Read/write text files with line ranges |
| **MCP Integration** | ✅ | Stdio, HTTP, and SSE transports |
| **Permissions** | ✅ | Interactive UI with diff preview for tool approval |
| **Session Management** | ✅ | Create, load, and persist sessions with state tracking |
| **Session Modes** | ✅ | Mode switching  |
| **Session Models** | ✅ | Select specific models |
| **Tool Calls** | ✅ | Content blocks, file diffs, status updates |
| **Agent Plans** | ❌ | Visual display of an agent's execution plan |
| **Terminal Operations** | ❌        | Terminal capabilities not implemented |


### Supported Adapters

Please see the [Configuring ACP Adapters](/configuration/adapters-acp) page.

### Client Capabilities

CodeCompanion advertises the following capabilities to ACP agents:

```lua
{
  fs = {
    readTextFile = true,   -- Read files with optional line ranges
    writeTextFile = true   -- Write/create files
  },
  terminal = false         -- Terminal operations not supported
}
```

### Content Types


| Content Type | Send to Agent | Receive from Agent |
|--------------|---------------|-------------------|
| Text | ✅ | ✅ |
| File Diffs | N/A | ✅ |
| Images | ✅ | ❌ |
| Audio | ❌ | ❌ |
| Embedded Resources | ❌ | ❌ |


### State Management

Unlike HTTP adapters which are stateless (sending the full conversation history with each request), ACP adapters are stateful. The agent maintains the conversation context, so CodeCompanion only sends new messages with each prompt. Session IDs are tracked throughout the conversation lifecycle.

### File Context Handling

When sending files as embedded resources to agents, CodeCompanion re-reads the file content rather than using the chat buffer representation. This avoids HTTP-style `<attachment>` tags that are used for LLM adapters but don't make sense for ACP agents.

### Slash Commands

ACP agents can advertise their own slash commands dynamically. You can access them with `\command` in the chat buffer. CodeCompanion transforms this to `/command` before sending your prompt to the agent.

### Model Selection

CodeCompanion implements a `session/set_model` method that allows you to select a model for the current session. This feature is not part of the [official ACP specification](https://agentclientprotocol.com/protocol/draft/schema#session-set_model) and is subject to change in future versions.

### Cleanup and Lifecycle

CodeCompanion ensures clean disconnection from ACP agents by hooking into Neovim's `VimLeavePre` autocmd. This guarantees that agent processes are properly terminated even if Neovim exits unexpectedly.

## Protocol Version

CodeCompanion currently implements **ACP Protocol Version 1**.

The protocol version is negotiated during initialization. If an agent selects a different version, CodeCompanion will log a warning but continue to operate, following the agent's selected version.

## Current Limitations

- **Terminal Operations**: The `terminal/*` family of methods (`terminal/create`, `terminal/output`, `terminal/release`, etc.) are not implemented. CodeCompanion doesn't advertise terminal capabilities to agents.

- **Agent Plan Rendering**: [Plan](https://agentclientprotocol.com/protocol/agent-plan) updates from agents are received and logged, but they're not currently rendered in the chat buffer UI.

- **Audio Content**: Audio can't be sent or received

## See Also

- [Agent Client Protocol Specification](https://agentclientprotocol.com/) - Official ACP documentation
- [Configuring ACP Adapters](/configuration/adapters-acp) - Setup instructions for specific agents
- [Using Agents](/usage/chat-buffer/agents) - How to interact with agents in chat

