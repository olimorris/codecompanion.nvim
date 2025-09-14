# ACP (Agent Client Protocol) in CodeCompanion.nvim

ACP (Agent Client Protocol) is a JSON-RPC based protocol that enables sophisticated communication between CodeCompanion.nvim and AI agents like Claude Code and Gemini CLI. Unlike traditional HTTP-based API calls, ACP provides session-based interactions with streaming responses, tool execution, and interactive permission handling.

## What is ACP?

@.codecompanion/acp/acp_json_schema.json

ACP is a protocol specification that defines how clients (like CodeCompanion.nvim) communicate with AI agents through a standardized message format. Key features include:

- **Session Management**: Persistent conversation contexts across multiple interactions
- **Streaming Responses**: Real-time message delivery as the agent processes requests
- **Tool Execution**: Agents can execute tools (file operations, shell commands, etc.) with user permission
- **Authentication**: Secure authentication methods including OAuth tokens and API keys
- **Permission System**: Interactive approval system for potentially sensitive operations

## Architecture Overview

### Core Components

#### ACP Connection

@./lua/codecompanion/acp/init.lua

The main ACP connection manager that handles:
- Process spawning and lifecycle management
- JSON-RPC message parsing and routing
- Session initialization and authentication
- Request/response correlation
- Error handling and timeout management

#### ACP Adapters

@./lua/codecompanion/adapters/acp/claude_code.lua
@./lua/codecompanion/adapters/acp/helpers.lua

Adapter implementations for specific ACP agents:

- `claude_code.lua` - Claude Code agent integration
- `gemini_cli.lua` - Gemini CLI agent integration
- `helpers.lua` - Shared utilities for ACP adapters

#### Prompt Builder

@./lua/codecompanion/acp/prompt_builder.lua

A fluent API for constructing and sending prompts with streaming response handling:

```lua
local prompt = PromptBuilder.new(connection, messages)
  :on_message_chunk(function(chunk) ... end)
  :on_thought_chunk(function(thought) ... end)
  :on_tool_call(function(tool) ... end)
  :with_options({ bufnr = bufnr })
  :send()
```

#### ACP Handlers

@./lua/codecompanion/strategies/chat/acp/handler.lua
@./lua/codecompanion/strategies/chat/acp/request_permission.lua

Chat-specific ACP integration:
- `handler.lua` - Main chat buffer ACP handler
- `request_permission.lua` - Interactive permission request UI

## Message Flow

### 1. Initialization

```
Client → Agent: initialize request
Agent → Client: capabilities and auth methods
```

### 2. Authentication

```
Client → Agent: authenticate request
Agent → Client: success/failure response
```

### 3. Session Creation

```
Client → Agent: session/new request
Agent → Client: session ID
```

### 4. Prompt Exchange

```
Client → Agent: session/prompt request
Agent → Client: streaming session/update notifications
```

### 5. Tool Execution

```
Agent → Client: session/request_permission
Client → Agent: permission response
Agent → Client: tool execution results
```

## Key ACP Message Types

### Session Updates

- `agent_message_chunk` - Streamed response content
- `agent_thought_chunk` - Agent reasoning/planning
- `tool_call` - Tool execution request
- `tool_call_update` - Tool execution progress/completion
- `plan` - High-level execution plan

### Permission Requests

When agents need to execute potentially sensitive operations, they request permission. This can come in two forms:

#### 1. Tool calls with permission

```json
{
  "method": "session/request_permission",
  "params": {
    "sessionId": "abc123",
    "options": [
      {"optionId": "allow_once", "name": "Allow", "kind": "allow_once"},
      {"optionId": "reject", "name": "Reject", "kind": "reject_once"}
    ],
    "toolCall": {
      "title": "Writing to config.lua",
      "kind": "edit",
      "content": [{"type": "diff", "path": "config.lua", ...}]
    }
  }
}
```

#### 2. Tool calls followed by permission

> Note that the two calls below are linked by the `toolCallId`:

```json
{
    "jsonrpc": "2.0",
    "method": "session/update",
    "params": {
        "sessionId": "01992f51-373e-772d-9632-bb7d38a8d47b",
        "update": {
            "toolCallId": "toolu_01FzKhxc4Mo5abCyAipUdLo3",
            "sessionUpdate": "tool_call",
            "status": "pending",
            "title": "Edit `/Some/Path/Neovim/codecompanion.nvim/test.txt`",
            "kind": "edit",
            "content": [
                {
                    "type": "diff",
                    "path": "/Some/Path/Code/Neovim/codecompanion.nvim/test.txt",
                    "oldText": "Hello World",
                    "newText": "Hello World\nHave a wonderful day! 🌟"
                }
            ],
            "locations": [
                {
                    "path": "/Some/Path/Code/Neovim/codecompanion.nvim/test.txt"
                }
            ]
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
        "options": [
            {
                "kind": "allow_always",
                "name": "Always Allow",
                "optionId": "allow_always"
            },
            {
                "kind": "allow_once",
                "name": "Allow",
                "optionId": "allow"
            },
            {
                "kind": "reject_once",
                "name": "Reject",
                "optionId": "reject"
            }
        ],
        "sessionId": "01992f51-373e-772d-9632-bb7d38a8d47b",
        "toolCall": {
            "toolCallId": "toolu_01FzKhxc4Mo5abCyAipUdLo3"
        }
    }
}
```

## Integration with Chat Buffer

ACP is seamlessly integrated into CodeCompanion's chat buffer experience:

1. **User Input**: User types message in chat buffer
2. **Message Parsing**: Tree-sitter extracts user content
3. **ACP Submission**: If ACP adapter is selected, message sent via ACP
4. **Streaming Display**: Agent responses stream into buffer in real-time
5. **Tool Visualization**: Tool calls and results displayed with appropriate formatting
6. **Permission Dialogs**: Interactive prompts for tool execution approval

## Configuration

ACP adapters are configured in the main config:

```lua
adapters = {
  claude_code = {
    name = "claude_code",
    type = "acp",
    commands = {
      default = {"npx", "--yes", "@zed-industries/claude-code-acp"}
    },
    env = {
      CLAUDE_CODE_OAUTH_TOKEN = "your_token_here"
    }
  }
}
```

## Supported Agents

### Claude Code

Official Claude Code agent with:
- OAuth authentication
- File system operations
- Vision support
- Comprehensive tool suite

### Gemini CLI

Google's Gemini CLI agent with:
- API key authentication
- Code generation and analysis
- Multi-modal support

## File System Integration

ACP agents can interact with the file system through standardized methods:

- `fs/read_text_file` - Read file contents
- `fs/write_text_file` - Write file contents

All file operations require user permission and show diffs when applicable. The file containing this logic is:

@./lua/codecompanion/strategies/chat/acp/fs.lua

## Error Handling

Robust error handling throughout the ACP stack:
- Connection failures and timeouts
- Authentication errors
- Protocol version mismatches
- Tool execution failures
- Graceful degradation when agents become unavailable
