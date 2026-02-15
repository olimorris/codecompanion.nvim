# CLAUDE.md - CodeCompanion.nvim

Neovim plugin (Lua) providing LLM-powered coding assistance: chat, inline transforms, and extensible tools.

## Commands

- `make format` — StyLua (120 cols, 2 spaces). Run before committing.
- `make test` — full test suite (Mini.Test)
- `make test_file FILE=path` — targeted tests
- `make docs` — regenerate vimdoc

## Code Conventions

- **Naming:** snake_case for files/functions, PascalCase for classes, underscore prefix for private functions
- **Explicit names:** `pattern` not `pat`, `should_include` not `include_ok`
- **Function params:** prefer a single table argument over positional args
- **Error handling:** `pcall` + `log:error()`, return nil on failure
- **Type annotations:** LuaCATS for public APIs
- **Functions:** keep under 50 lines
- **Globals:** avoid; use module-local state
- **Code blocks:** use four backticks with language spec

## Architecture

Core: `lua/codecompanion/`

- **Interactions** (`interactions/`): `chat/`, `inline/`, `cmd.lua`, `init.lua` (workflows)
- **Adapters** (`adapters/`): `http/` (Anthropic, OpenAI, Copilot, Ollama, Gemini, etc.), `acp/` (Claude Code, Codex, etc.)
- **Tools** (`interactions/chat/tools/builtin/`): `run_command`, `read_file`, `create_file`, `delete_file`, `insert_edit_into_file/`, `grep_search`, `file_search`, `web_search`, `fetch_webpage`, `memory`, `next_edit_suggestion`, `get_changed_files`, `cmd_tool` (factory for custom command tools)
- **Slash Commands** (`interactions/chat/slash_commands/builtin/`): `/buffer`, `/file`, `/fetch`, `/symbols`, `/help`, `/image`, `/quickfix`, `/terminal`, `/mode`, `/memory`, `/now`
- **Editor Context** (`interactions/chat/editor_context/`): `buffer`, `lsp`, `user`, `viewport`
- **Config:** `config.lua` — tool groups (`full_stack_dev`, `files`), adapter defaults, all settings
- **Entry point:** `plugin/codecompanion.lua` → `lua/codecompanion/init.lua`

## Important Instructions

Do what has been asked; nothing more, nothing less.
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files
- NEVER proactively create documentation files
