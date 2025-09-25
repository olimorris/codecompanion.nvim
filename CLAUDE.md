# CodeCompanion.nvim

Neovim plugin providing LLM-powered coding assistance with chat interface, inline code transformation, and extensible tools.

## Architecture

- **Strategies**: Chat, inline, and cmd interaction modes
- **Adapters**: LLM provider integrations (HTTP and ACP)
- **Tools**: LLM-executable functions for file operations
- **Variables**: Dynamic context injection (buffers, LSP diagnostics)

## Coding Standards

### Naming
- Use explicit names (`pattern` not `pat`)
- Functions should describe their action (`should_include` not `include_ok`)
- Make conditionals readable: `if should_include(pattern) then`

### Lua Style
- Format with StyLua (120 column width, 2 spaces)
- Use LuaCATS type annotations
- Consistent error handling with logging

### Patterns

````lua
-- Configuration
local defaults = { strategies = { chat = { adapter = "copilot" } } }
local M = { config = vim.deepcopy(defaults) }
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args or {})
end

-- Error handling
local log = require("codecompanion.utils.log")
local ok, result = pcall(some_function)
if not ok then
  log:error("Operation failed: %s", result)
  return nil
end
````

### Testing
- Use Mini.Test
- Run with `make test` or `make test_file FILE=path`

## Development
- **Format**: `make format`
- **Test**: `make test`
- **Docs**: `make docs`

Keep functions under 50 lines, use descriptive names, and ensure all public APIs have type annotations.

## Important Instructions

Do what has been asked; nothing more, nothing less.
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files
- NEVER proactively create documentation files
- Use four backticks for code blocks with language specification

````lua
-- Your code here
````