# ACP Integration in CodeCompanion.nvim: Comprehensive Overview

This document explains how CodeCompanion.nvim integrates the **Agent Communication Protocol (ACP)** to enable advanced, session-based interactions with Large Language Models (LLMs) and agents. It covers the architecture, workflow, message schema, and how ACP fits into the chat buffer experience.

---

## 1. **What is ACP?**

ACP (Agent Communication Protocol) is a JSON-RPC-based protocol designed for robust, multi-turn, session-oriented communication between clients (like CodeCompanion.nvim) and AI agents. It supports authentication, session management, streaming responses, tool calls, and permission handling.

ACP is schema-driven, with a [JSON schema](llm_notes/acp_json_schema.json) that defines all request, response, and notification types exchanged between client and agent.

---

## 2. **ACP in CodeCompanion.nvim: Architectural Integration**

### **Adapter Pattern**

- **ACPAdapter**: CodeCompanion uses an adapter abstraction (`ACPadapter`) to encapsulate ACP-specific logic. This allows the chat buffer to interact with ACP agents in a unified way, regardless of the underlying agent implementation.

### **Connection Management**

- **ACPConnection**: Handles process spawning, session lifecycle, authentication, and streaming communication with the agent.
- **PromptBuilder**: Fluent API for constructing and sending prompts, handling streamed responses, tool calls, and errors.

### **Chat Buffer Workflow**

1. **User Types Message**: In a Markdown-formatted Neovim buffer, under an H2 header.
2. **Tree-sitter Parsing**: The buffer is parsed to extract the user's message.
3. **ACP Adapter Selection**: The chat buffer uses the ACP adapter if configured.
4. **Session Management**: ACPConnection initializes, authenticates, and creates a session with the agent.
5. **Prompt Submission**: The user's message is sent as a `session/prompt` ACP request.
6. **Streaming Response**: The agent streams back responses, thoughts, and tool calls, which are rendered in the buffer.
7. **Tool Execution & Permissions**: If the agent requests tool execution or permissions, CodeCompanion handles these via ACP notifications and requests.

---

## 3. **ACP Message Flow: Key Steps**

### **Initialization**

- **Client → Agent**: `initialize` request (see `InitializeRequest` in schema)
  - Includes client capabilities (e.g., file system access), protocol version.
- **Agent → Client**: `InitializeResponse`
  - Returns supported agent capabilities, authentication methods, protocol version.

### **Authentication**

- **Client → Agent**: `authenticate` request (`AuthenticateRequest`)
  - Specifies authentication method (e.g., API key).
- **Agent → Client**: `AuthenticateResponse`
  - Indicates success/failure.

### **Session Creation**

- **Client → Agent**: `session/new` request (`NewSessionRequest`)
  - Includes working directory, MCP servers.
- **Agent → Client**: `NewSessionResponse`
  - Returns session ID.

### **Prompting**

- **Client → Agent**: `session/prompt` request (`PromptRequest`)
  - Contains session ID and an array of `ContentBlock` objects (parsed from buffer).
- **Agent → Client**: Streaming `SessionNotification`
  - Types:
    - `agent_message_chunk`: LLM's streamed response.
    - `agent_thought_chunk`: LLM's reasoning or plan.
    - `tool_call` / `tool_call_update`: Tool execution requests and updates.
    - `plan`: High-level execution plan.
  - Each notification includes session ID and update payload.

### **Tool Calls & Permissions**

- **Agent → Client**: `session/request_permission` notification
  - Requests permission for tool execution, with options (`PermissionOption`).
- **Client → Agent**: `RequestPermissionResponse`
  - User selects allow/reject; response sent back to agent.

### **Session Lifecycle**

- **Session Load/Save**: ACP supports loading and saving sessions (`session/load`), enabling persistent conversations.
- **Cancel**: Client can send `CancelNotification` to abort a turn.

---

## 4. **ACP Schema: Key Types and Their Use**

Referencing [`acp_json_schema.json`](llm_notes/acp_json_schema.json):

- **ContentBlock**: Core unit for messages, supporting text, images, audio, resource links, and embedded resources.
- **SessionNotification**: Used for streaming agent responses, thoughts, tool calls, and plans.
- **ToolCall**: Structure for tool execution requests, including kind, status, locations, and content.
- **PermissionOption/RequestPermissionRequest**: Used for interactive permission handling when agent wants to execute tools.
- **StopReason**: Indicates why a turn ended (e.g., success, max tokens, refusal, cancelled).

---

## 5. **CodeCompanion ACP Implementation Details**

### **ACPConnection (lua/codecompanion/acp.lua)**

- **Process Management**: Spawns agent process, manages stdin/stdout, buffers output for JSON-RPC message boundaries.
- **Session State**: Tracks initialization, authentication, session ID, pending responses.
- **Request/Response Handling**: Synchronous requests (initialize, authenticate, session/new), streaming notifications.
- **Permission Handling**: Presents permission dialogs to user, sends outcome to agent.

### **PromptBuilder**

- **Fluent API**: Allows chaining handlers for message chunks, thought chunks, tool calls, completion, and errors.
- **Streaming**: Handles streamed agent responses, updating the chat buffer in real time.

### **Chat Buffer (lua/codecompanion/strategies/chat/init.lua)**

- **Message Parsing**: Uses Tree-sitter to extract user messages and context.
- **ACP Submission**: If ACP adapter is selected, uses ACPConnection to submit prompt and handle streaming responses.
- **Buffer Updates**: Streams agent responses, thoughts, and tool outputs into the buffer under appropriate headers.

---

## 6. **Example ACP Message Exchange**

**User Prompt:**
```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "session/prompt",
  "params": {
    "sessionId": "abc123",
    "prompt": [
      { "type": "text", "text": "How do I use the grep_search tool?" }
    ]
  }
}
```

**Agent Streaming Response:**
```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "abc123",
    "update": {
      "sessionUpdate": "agent_thought_chunk",
      "content": { "type": "text", "text": "Thinking about how to search for code..." }
    }
  }
}
```
```json
{
    "jsonrpc": "2.0",
    "id": 0,
    "method": "session/request_permission",
    "params": {
        "sessionId": "370030f3-a287-4054-b2a7-010b4bb084e8",
        "options": [
            {
                "optionId": "proceed_always",
                "name": "Allow All Edits",
                "kind": "allow_always"
            },
            {
                "optionId": "proceed_once",
                "name": "Allow",
                "kind": "allow_once"
            },
            {
                "optionId": "cancel",
                "name": "Reject",
                "kind": "reject_once"
            }
        ],
        "toolCall": {
            "toolCallId": "write_file-1754861800410",
            "status": "pending",
            "title": "Writing to test.txt",
            "content": [
                {
                    "type": "diff",
                    "path": "test.txt",
                    "oldText": "This is some old text",
                    "newText": "This is some new text"
                }
            ],
            "locations": [],
            "kind": "edit"
        }
    }
}

```
```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "abc123",
    "update": {
      "sessionUpdate": "tool_call",
      "toolCallId": "call_xyz",
      "title": "Grep Search",
      "kind": "search",
      "status": "pending",
      "content": []
    }
  }
}
```
```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "abc123",
    "update": {
      "sessionUpdate": "agent_message_chunk",
      "content": { "type": "text", "text": "Here are the results of your search..." }
    }
  }
}
```

---

## 7. **Summary Table: ACP Workflow in CodeCompanion**

| Step                | ACP Message Type         | CodeCompanion Component      | Buffer Effect                |
|---------------------|-------------------------|-----------------------------|------------------------------|
| Initialization      | `initialize`            | ACPConnection               | Setup agent process/session  |
| Authentication      | `authenticate`          | ACPConnection               | Auth dialog if needed        |
| Session Creation    | `session/new`           | ACPConnection               | Session ID assigned          |
| Prompt Submission   | `session/prompt`        | PromptBuilder/Chat Buffer   | User message sent            |
| Streaming Response  | `session/update`        | PromptBuilder/Chat Buffer   | LLM/agent responses streamed |
| Tool Calls          | `tool_call`/`tool_call_update` | PromptBuilder/Chat Buffer | Tool execution requests      |
| Permission Request  | `session/request_permission` | ACPConnection/Chat Buffer | User permission dialog       |
| Completion          | `PromptResponse`        | PromptBuilder/Chat Buffer   | End of turn, ready for next  |

---

## 8. **Extensibility and Schema Awareness**

- **Schema-Driven**: All ACP interactions are validated and mapped according to the schema, ensuring compatibility and extensibility.
- **Event-Driven**: CodeCompanion fires events for key ACP lifecycle moments (request started, streaming, finished, permission requested), allowing plugins and workflows to hook in.
- **Tooling**: ACP enables rich tool integration, with permission gating and streaming updates.

---

## 9. **References**

- [ACP JSON Schema](llm_notes/acp_json_schema.json)
- `lua/codecompanion/acp.lua` (ACPConnection, PromptBuilder)
- `lua/codecompanion/strategies/chat/init.lua` (Chat Buffer logic)
- [Zed ACP Protocol Reference](https://github.com/zed-industries/agent-protocol)

---

## 10. **Conclusion**

ACP integration in CodeCompanion.nvim provides a powerful, extensible, and schema-driven foundation for conversational AI, tool automation, and session management. By leveraging ACP, CodeCompanion can support advanced agent features, robust tool workflows, and interactive permission handling—all seamlessly integrated into the Neovim chat buffer experience.

