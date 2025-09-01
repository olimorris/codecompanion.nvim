# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- `make test` - Run all tests using Mini.Test framework
- `make test_file FILE=path/to/test.lua` - Run a specific test file
- Tests run headless with minimal init configuration

### Formatting and Linting
- `make format` - Format Lua code using StyLua with project configuration
- Configuration in `stylua.toml`: 2-space indents, 120 column width, Unix line endings

### Documentation
- `make docs` - Generate vim documentation from markdown using panvimdoc

### Development Setup
- `make deps` - Clone required dependencies (plenary.nvim, nvim-treesitter, mini.nvim)
- Dependencies are cloned to `deps/` directory for testing

## Architecture

CodeCompanion.nvim is a Neovim plugin that integrates LLMs using three core strategies: Chat, Inline, and Tools. The plugin follows several key design patterns:

### Core Components

**Adapter Pattern**: Unified interface for multiple LLM providers (Anthropic, OpenAI, Copilot, etc.) through HTTP adapters and ACP (Agent Client Protocol) adapters. All adapters implement consistent schema validation and request/response handling.

**Strategy Pattern**: Three main interaction modes:
- **Chat** (`lua/codecompanion/strategies/chat/`) - Conversational interface using markdown-formatted buffers
- **Inline** (`lua/codecompanion/strategies/inline/`) - Direct code generation and editing
- **Tools** (`lua/codecompanion/strategies/chat/tools/`) - Function calling system for LLM automation

**Builder Pattern**: The chat UI uses a builder pattern (`lua/codecompanion/strategies/chat/ui/builder.lua`) with specialized formatters for different message types (tools, reasoning, standard content).

### Key Architecture Files

- `lua/codecompanion/adapters/` - LLM provider implementations
- `lua/codecompanion/strategies/chat/` - Chat buffer logic and UI management
- `lua/codecompanion/acp/` - Agent Client Protocol implementation for session-based communication
- `lua/codecompanion/http.lua` - HTTP client for adapter communication
- `lua/codecompanion/config.lua` - Plugin configuration and defaults

### Chat Buffer System

The chat buffer is a markdown-formatted Neovim buffer that uses Tree-sitter parsing to extract user messages and stream LLM responses. It supports:
- Variables and context injection
- Slash commands for enhanced functionality
- Tool execution with visual feedback
- Folding for tool output and context sections

### Testing Framework

Uses Mini.Test for comprehensive testing including:
- Unit tests for core functionality
- Integration tests with screenshot comparison
- Test helpers in `tests/helpers.lua`
- Minimal init configuration in `scripts/minimal_init.lua`

### ACP Integration

Supports Agent Client Protocol for session-based communication with agents like Gemini CLI. Key components:
- `ACPConnection` - Session management and streaming
- `PromptBuilder` - Fluent API for prompt construction
- Request permission handling for file operations

The codebase emphasizes modularity, testability, and extensibility through clear separation of concerns and well-defined interfaces between components.