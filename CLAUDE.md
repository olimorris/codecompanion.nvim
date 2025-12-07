# CLAUDE.md - CodeCompanion.nvim Development Guide

## Overview

This document provides guidance for Claude Code when working with the CodeCompanion.nvim repository. CodeCompanion.nvim is a Neovim plugin written in Lua that provides LLM-powered coding assistance with chat interface, inline code transformation, and extensible tools.

## Essential Guidelines

**Development Commands:**
- Always use `make format` before committing changes
- Run `make test` to execute the full test suite
- Use `make test_file FILE=path` for targeted test execution
- Generate documentation with `make docs`

**Testing Requirements:**
- Use Mini.Test framework for all tests
- Mock external dependencies appropriately
- Ensure tests pass locally before pushing

**Code Quality:**
- Format all code with StyLua (120 column width, 2 spaces)
- Use LuaCATS type annotations for all public APIs
- Keep functions under 50 lines for maintainability

## Architecture

**Core Location:** `lua/codecompanion/`

### Strategies (Interaction Modes)

Located in `lua/codecompanion/interactions/`:

**Chat Strategy** (`strategies/chat/`)
- Primary interactive mode with buffer-based interface
- Key components: `ui/`, `tools/`, `slash_commands/`, `memory/`, `variables/`, `edit_tracker.lua`, `parser.lua`

**Inline Strategy** (`strategies/inline/`)
- Direct code transformation in Neovim buffers
- Supports multiple placement modes (buffer, replace, new file)

**Cmd Strategy** (`strategies/cmd.lua`)
- Command-line style lightweight query-response interface

**Workflow Strategy** (`strategies/init.lua`)
- Multi-stage prompts with subscribers for complex interactions

### Adapters (LLM Providers)

Located in `lua/codecompanion/adapters/`:

**HTTP Adapters** (`adapters/http/`): Anthropic, OpenAI, Copilot, Ollama, Gemini, Mistral, Deepseek, Azure OpenAI, GitHub Models, HuggingFace, XAI, Jina, Tavily, Novita, and OpenAI-compatible servers.

**ACP Adapters** (`adapters/acp/`): Claude Code, Auggie CLI, Codex, Gemini CLI (Agent Client Protocol).

### Tools System (Function Calling)

Located in `lua/codecompanion/interactions/chat/tools/builtin/`:

**File Operations:** `read_file`, `create_file`, `delete_file`, `insert_edit_into_file/` (advanced editing with multiple matching strategies)

**Code Analysis:** `list_code_usages/` (LSP-based), `grep_search`, `file_search`

**Execution & Web:** `cmd_runner`, `web_search`, `fetch_webpage`

**Utilities:** `memory`, `next_edit_suggestion`, `get_changed_files`

Tool groups (e.g., `full_stack_dev`) defined in config. Orchestration via `tools/init.lua`.

### Slash Commands (Context Injection)

Located in `lua/codecompanion/interactions/chat/slash_commands/builtin/`:

`/buffer`, `/file`, `/fetch`, `/symbols`, `/help`, `/image`, `/quickfix`, `/terminal`, `/mode`, `/memory`, `/now`

Dynamic context ingestion via `/command` syntax in chat.

### Variables & Interactions

**Variables** (`strategies/chat/variables/`): `buffer`, `lsp`, `user`, `viewport` - expanded in system prompts and messages.

**Background Interactions** (`interactions/background/`): Auto-run LLM tasks with event hooks (e.g., `chat_make_title` auto-generates chat titles).

### Providers & Extensions

**Providers** (`providers/`): Completion (blink, cmp, coc), actions, diff, slash_commands.

**Extensions** (`_extensions/`): Third-party extension registration system.

## Technology Stack

Lua + Neovim API. Testing with Mini.Test. Dependencies: plenary.nvim, nvim-treesitter, mini.nvim. Docs via panvimdoc.

## Development Patterns

**Lua Standards:**
- Use explicit names (`pattern` not `pat`)
- Functions describe action (`should_include` not `include_ok`)
- Make conditionals readable
- Avoid globals; use module-local state

**Error Handling:**
````lua
local log = require("codecompanion.utils.log")
local ok, result = pcall(some_function)
if not ok then
  log:error("Operation failed: %s", result)
  return nil
end
````

**Configuration Pattern:**
````lua
local defaults = { strategies = { chat = { adapter = "copilot" } } }
local M = { config = vim.deepcopy(defaults) }
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args or {})
end
````

**Testing:**
- Place tests in `tests/` mirroring source structure
- Use descriptive test names
- Mock external dependencies
- Ensure test isolation

## Key Architectural Patterns

**Message Flow:**
````
User Input → Strategy → Adapter → LLM
LLM Response → Parser → Tools (optional) → Chat Buffer Display
````

**Tool Execution:**
1. LLM returns tool calls
2. Orchestrator extracts and validates
3. Tools execute with LLM arguments
4. Results sent back to LLM

**Context Injection:**
- Variables: Expanded in system prompt
- Slash Commands: User-triggered context
- Buffer Watching: Automatic tracking

## File Organization

**Key Files:**
- `plugin/codecompanion.lua` - Plugin entry point
- `lua/codecompanion/init.lua` - Main module and public API
- `lua/codecompanion/config.lua` - Configuration management
- `lua/codecompanion/types.lua` - LuaCATS type definitions
- `lua/codecompanion/http.lua` - HTTP client

**Utilities** (`utils/`): `adapters`, `buffers`, `files`, `log`, `keymaps`, `context`, `images`, `async`, `tokens`, `treesitter`, `tool_transformers`

**Naming Conventions:**
- snake_case for files and functions
- PascalCase for classes/objects
- Underscore prefix for private functions

## Important Instructions

Do what has been asked; nothing more, nothing less.
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files
- NEVER proactively create documentation files
- Use four backticks for code blocks with language specification

````lua
-- Your code here
````

