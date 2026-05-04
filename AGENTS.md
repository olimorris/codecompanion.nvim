# CodeCompanion.nvim

This is a Neovim plugin written in Lua, which allows developers to code with LLMs and agents from within Neovim. Tests use Mini.Test with child processes. Always run the full test suite after changes and ensure all tests pass before considering work complete.

## Commands

- `make format` — StyLua (120 cols, 2 spaces). Run before committing.
- `make test` — full test suite (Mini.Test)
- `make test_file FILE=path` — targeted tests
- `make docs` — regenerate vimdoc. Run this after changing any docs pages

## Code conventions

- **Naming:** snake_case for files/functions, PascalCase for classes, underscore prefix for private functions
- **Explicit names:** `pattern` not `pat`, `should_include` not `include_ok`
- **Readable code:** names, variables, and control flow should read like clean English. Avoid generic names like `ctx` — use domain-specific names (`permission`, `request`, `source`)
- **Plain language:** avoid jargon shortcuts in code, comments, commit messages, and chat. Don't say "no-op" — say what the code actually does ("returns unchanged", "does nothing", "skipped because already edited")
- **Function params:** prefer a single table argument over positional args
- **Error handling:** `pcall` + `log:error()`, return nil on failure
- **Type annotations:** LuaCATS for public APIs. Keep doc blocks concise — one description line, params should be self-explanatory without inline comments
- **Functions:** keep under 50 lines
- **Globals:** avoid; use module-local state
- **Code blocks:** use four backticks with language spec

## Architecture

Core: `lua/codecompanion/`

- **Interactions** (`interactions/`): `chat/`, `inline/`, `cmd.lua`, `init.lua` (workflows)
- **Adapters** (`adapters/`): `http/` (Anthropic, OpenAI, Copilot, Ollama, Gemini, etc.), `acp/` (Claude Code, Codex, etc.)
- **Tools** (`interactions/chat/tools/builtin/`): `ask_questions`, `run_command`, `read_file`, `create_file`, `delete_file`, `insert_edit_into_file/`, `grep_search`, `file_search`, `web_search`, `fetch_webpage`, `memory`, `get_changed_files`, `get_diagnostics`, `cmd_tool` (factory for custom command tools)
- **Slash Commands** (`interactions/chat/slash_commands/builtin/`): `/buffer`, `/command`, `/compact`, `/fetch`, `/file`, `/help`, `/image`, `/mcp`, `/mode`, `/now`, `/rules`, `/symbols`
- **Editor Context** (`interactions/chat/editor_context/`): `buffer`, `buffers`, `diagnostics`, `diff`, `messages`, `quickfix`, `selection`, `terminal`, `viewport`
- **Config:** `config.lua` — tool groups (`agent`, `files`), adapter defaults, all settings
- **Entry point:** `plugin/codecompanion.lua` → `lua/codecompanion/init.lua`

## General rules

- Don't over-explore the codebase with excessive grep/read calls. If you haven't converged on an approach after 3-4 searches, pause and share what you've found so far rather than continuing to search.
- When the user asks to fix tests, fix the tests — not the source code — unless explicitly asked otherwise.

## Important instructions

- Do what has been asked; nothing more, nothing less.
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files
- NEVER proactively create documentation files
- ALWAYS keep memory in the current working directory and `memories/` folder

### Self-improvement loop

The user may have shared a `PERSONAL.md` file with specific instructions for how they like to work. If so, follow these instructions carefully:

- Review the `PERSONAL.md` at the start of every session
- After ANY correction from the user: update the `PERSONAL.md` with the pattern
- Write rules that prevent the same mistake from happening again

