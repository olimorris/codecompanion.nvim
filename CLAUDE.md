# CodeCompanion.nvim

## What is CodeCompanion?

@./lua/codecompanion/strategies/chat/init.lua

CodeCompanion.nvim is a sophisticated Neovim plugin that brings LLM-powered coding assistance directly into your editor. Think of it as "Copilot Chat meets Zed AI, in Neovim" - it provides an integrated chat interface for conversing with large language models while maintaining full context of your codebase.

### Core Features

- **Chat Interface**: Interactive chat buffer for conversing with LLMs from Anthropic, OpenAI, GitHub Copilot, Gemini, and many others
- **Agent Client Protocol (ACP)**: Support for agents like Claude Code and Gemini CLI
- **Inline Assistant**: Transform code directly in your buffer with LLM suggestions
- **Tools & Workflows**: Extensible system for LLMs to read files, search code, run commands, and modify your codebase
- **Variables & Slash Commands**: Context injection system to share buffers, LSP info, and more with LLMs
- **Prompt Library**: Built-in prompts for common tasks like code explanation, unit tests, and bug fixes
- **Multi-Chat Support**: Have multiple chat sessions open simultaneously
- **Vision Support**: Share images and screenshots with vision-capable models

### Architecture

CodeCompanion follows a modular architecture with clear separation of concerns:

- **Strategies**: Different interaction modes (chat, inline, cmd)
- **Adapters**: LLM provider integrations (HTTP and ACP based)
- **Providers**: UI integrations (Telescope, fzf-lua, mini.pick, etc.)
- **Tools**: LLM-executable functions for file operations, searches, etc.
- **Variables**: Dynamic content injection (buffers, LSP diagnostics, etc.)
- **Slash Commands**: User-triggered context addition

## Coding Standards

### General Principles

- **Modularity**: Each component has a single, well-defined responsibility
- **Configuration-Driven**: Extensive customization through structured configuration
- **Performance-First**: Async execution, lazy loading, and efficient Tree-sitter parsing
- **User Experience**: Intuitive keymaps, visual feedback, and error handling
- **Extensibility**: Plugin system for custom tools, variables, and slash commands

### Function and Variable Naming

- Favour being explicit over being overly concise.
  - For example: use `pattern` instead of `pat` for a variable holding a specific filepath pattern
- Function names should describe what they do, concisely.
  - For example: `should_include` instead of `include_ok` when determining if something should be added to a table
- When used in conditionals, variables and functions should make the conditional human readable.
  - For example: `if should_include(pattern) then`
- When working in `for` loops, it's okay to shorten an item's config values to `cfg` so as not to clash with any imports that may be named `config`.

### Lua Code Style

CodeCompanion follows strict Lua formatting standards enforced by StyLua:

```lua
-- Configuration (stylua.toml)
column_width = 120
indent_type = "Spaces"
indent_width = 2
line_endings = "Unix"
quote_style = "AutoPreferDouble"
no_call_parentheses = false
sort_requires = true
```

### Key Conventions

#### File Organization
```
lua/codecompanion/
├── adapters/           # LLM provider integrations
├── strategies/         # Chat, inline, and cmd interaction modes
│   ├── chat/          # Chat buffer implementation
│   └── inline/        # Inline code transformation
├── providers/          # UI provider integrations
├── utils/             # Shared utilities
└── config.lua         # Central configuration
```

#### Type Annotations

CodeCompanion uses extensive LuaCATS type annotations for better IDE support and documentation:

```lua
---@class CodeCompanion.Chat
---@field adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
---@field bufnr number The buffer number of the chat
---@field messages CodeCompanion.Chat.Messages
---@field tools CodeCompanion.Tools

---@param args CodeCompanion.ChatArgs
---@return CodeCompanion.Chat
function Chat.new(args)
```

#### Configuration Pattern

All components use a consistent configuration pattern:

```lua
local defaults = {
  strategies = {
    chat = {
      adapter = "copilot",
      tools = {},
      variables = {},
      slash_commands = {},
      keymaps = {},
      opts = {}
    }
  }
}

local M = {
  config = vim.deepcopy(defaults),
}

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args or {})
end
```

#### Error Handling

Consistent error handling with proper logging:

```lua
local log = require("codecompanion.utils.log")

local ok, result = pcall(some_function)
if not ok then
  log:error("Operation failed: %s", result)
  return nil
end
```

#### Async Patterns

CodeCompanion uses Plenary.nvim async patterns for HTTP requests and tool execution:

```lua
-- HTTP requests are non-blocking
local client = require("codecompanion.http").new({ adapter = settings })
client:request(payload, {
  callback = function(err, data) end,
  done = function() end
})
```

### Testing Standards

CodeCompanion uses Mini.Test for all testing:

```lua
-- File: tests/adapters/test_openai.lua
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Setup for each test
    end,
  },
})

T["can handle errors"] = function()
  -- Test implementation
end

return T
```

Run tests with:
```bash
make test                    # All tests
make test_file FILE=path     # Specific test file
```

### Documentation Standards

- **LuaCATS Annotations**: All public functions and classes must be documented
- **README**: Comprehensive user-facing documentation
- **CONTRIBUTING.md**: Developer documentation for contributors
- **Inline Comments**: Explain complex logic, not obvious code
- **Type Safety**: Extensive use of type annotations for IDE support

### Performance Considerations

- **Lazy Loading**: Modules are loaded on-demand
- **Tree-sitter Parsing**: Efficient parsing for chat buffer formatting
- **Async Execution**: Non-blocking operations for HTTP requests and tool execution
- **Memory Management**: Proper cleanup of autocmds, buffers, and connections
- **Caching**: Model and adapter information cached appropriately

### Extension Points

CodeCompanion provides several extension mechanisms:

1. **Custom Adapters**: Create adapters for new LLM providers
2. **Custom Tools**: Add new tools for LLMs to execute
3. **Custom Variables**: Add new context variables
4. **Custom Slash Commands**: Add new chat commands
5. **Custom Prompts**: Add prompts to the prompt library

### Development Workflow

1. **Format Code**: `make format` (StyLua)
2. **Run Tests**: `make test`
3. **Generate Docs**: `make docs` (panvimdoc)
4. **Use Minimal Config**: Test with `minimal.lua` for debugging

### Code Quality

- **No Magic Numbers**: Use named constants
- **Descriptive Names**: Variables and functions should be self-documenting
- **Small Functions**: Keep functions focused and under 50 lines when possible
- **Consistent Naming**: Use consistent patterns across the codebase
- **Error Messages**: Provide helpful, actionable error messages

## Development Guidelines

### Contributing

Before contributing:
1. Open a discussion to propose your idea
2. Follow the existing code patterns and style
3. Add comprehensive tests for new functionality
4. Update documentation and type annotations
5. Ensure all tests pass and code is formatted

### Architecture Decisions

- **Configuration First**: All behavior should be configurable
- **Provider Agnostic**: Support multiple UI providers (Telescope, fzf-lua, etc.)
- **Backward Compatibility**: Maintain API stability with deprecation warnings
- **Resource Management**: Proper cleanup of resources (buffers, autocmds, connections)

## Test

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.

## IMPORTANT

- If returning markdown code blocks, use four backticks (````) to open and close the code block, and specify the language (e.g., `lua`, `markdown`).
