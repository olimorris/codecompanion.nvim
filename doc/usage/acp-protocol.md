---
description: How CodeCompanion implements the Agent Client Protocol (ACP)
---

# ACP Protocol Reference

CodeCompanion implements the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/) to enable you to work with coding agents from within Neovim. ACP is an open standard that enables structured interaction between clients (like CodeCompanion) and AI agents, providing capabilities such as session management, file system operations, tool execution, and permission handling.

This page provides a technical reference for what's supported in CodeCompanion and how it's been implemented.

## Protocol Support

CodeCompanion provides comprehensive support for the ACP specification:

| Feature Category | Support Level | Details |
|------------------|---------------|---------|
| **Core Protocol** | ✅ Full | JSON-RPC 2.0, streaming responses, message buffering |
| **Session Management** | ✅ Full | Create, load, and persist sessions with state tracking |
| **Authentication** | ✅ Full | Multiple auth methods, adapter-level hooks |
| **File System** | ✅ Full | Read/write text files with line ranges |
| **Permissions** | ✅ Full | Interactive UI with diff preview for tool approval |
| **Content Types** | ✅ Full | Text, images, embedded resources |
| **Tool Calls** | ✅ Full | Content blocks, file diffs, status updates |
| **Session Modes** | ✅ Full | Mode switching and state management |
| **MCP Integration** | ✅ Full | Stdio, HTTP, and SSE transports |
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

### Content Support


| Content Type | Send to Agent | Receive from Agent |
|--------------|---------------|-------------------|
| Text | ✅ | ✅ |
| Images | ✅ | ✅ |
| Embedded Resources | ✅ | ✅ |
| Audio | ❌ | ❌ |
| File Diffs | N/A | ✅ |


### Session Updates Handled

CodeCompanion processes the following session update types:

- **Message chunks**: Streamed text from agent responses
- **Thought chunks**: Agent reasoning displayed separately
- **Tool calls**: Full execution lifecycle with status tracking
- **Mode changes**: Automatic UI updates when modes switch
- **Available commands**: Dynamic command registration for completion

## Implementation Notes

### Message Buffering

JSON-RPC message boundaries don't always align with I/O boundaries. CodeCompanion buffers stdout from the agent process and extracts complete JSON-RPC messages line-by-line, ensuring robust parsing even with partial reads.

### State Management

Unlike HTTP adapters which are stateless (sending the full conversation history with each request), ACP adapters are stateful. The agent maintains the conversation context, so CodeCompanion only sends new messages with each prompt. Session IDs are tracked throughout the conversation lifecycle.

### Tool Call Caching

Tool call state is maintained in memory to support permission requests. When an agent requests permission for a tool call, the cached details enable features like the diff preview UI for file edits.

### File Context Handling

When sending files as embedded resources to agents, CodeCompanion re-reads the file content rather than using the chat buffer representation. This avoids HTTP-style `<attachment>` tags that are used for LLM adapters but don't make sense for ACP agents.

### Slash Commands

ACP agents can advertise their own slash commands dynamically. You can access them with `\command` in the chat buffer. CodeCompanion transforms this to `/command` before sending your prompt to the agent.

### Model Selection

CodeCompanion implements a `session/set_model` method that allows you to select a model for the current session. This feature is not part of the [official ACP specification](https://agentclientprotocol.com/protocol/draft/schema#session-set_model) and is subject to change in future versions.

### Graceful Degradation

CodeCompanion checks an agent's capabilities during initialization and gracefully falls back to supported content types. For example, if an agent doesn't support embedded context, files are sent as plain text instead.

### Cleanup and Lifecycle

CodeCompanion ensures clean disconnection from ACP agents by hooking into Neovim's `VimLeavePre` autocmd. This guarantees that agent processes are properly terminated even if Neovim exits unexpectedly.

## Key Features

- **Streaming**: Real-time response streaming with chunk-by-chunk rendering
- **Permission System**: Interactive approval for file operations with diff preview
- **Session Persistence**: Resume previous conversations across Neovim sessions
- **Mode Management**: Switch between agent modes (e.g. ask, architect, code)
- **MCP Servers**: Connect agents to external tools via the Model Context Protocol
- **Slash Command Completion**: Auto-complete agent-specific commands with `\command` syntax
- **Error Handling**: Comprehensive error messages and graceful degradation

## Protocol Version

CodeCompanion currently implements **ACP Protocol Version 1**.

The protocol version is negotiated during initialization. If an agent selects a different version, CodeCompanion will log a warning but continue to operate, following the agent's selected version.

## Known Limitations

- **Terminal Operations**: The `terminal/*` family of methods (`terminal/create`, `terminal/output`, `terminal/release`, etc.) are not implemented. CodeCompanion doesn't advertise terminal capabilities to agents.

- **Agent Plan Rendering**: [Plan](https://agentclientprotocol.com/protocol/agent-plan) updates from agents are received and logged, but they're not currently rendered in the chat buffer UI.

- **Audio Content**: Audio content blocks aren't sent in prompts, despite capability detection.

## See Also

- [Configuring ACP Adapters](/configuration/adapters-acp) - Setup instructions for specific agents
- [Using Agents](/usage/chat-buffer/agents) - How to interact with agents in chat
- [Agent Client Protocol Specification](https://agentclientprotocol.com/) - Official ACP documentation

