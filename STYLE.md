# CodeCompanion Style Guide

This is the style contract for code in this repository. It applies to every PR, whether written by a human, an LLM, or both.

It exists because the most common reason a PR needs rework is not that the logic is wrong - it's that the code doesn't read like the rest of the codebase. Verbose comments, invented naming schemes, and test names that don't match the existing suite all cost review time and make the plugin harder to maintain long-term.

Read [CONTRIBUTING.md](CONTRIBUTING.md) first for what to contribute. This file covers how to write it.

## 1. Formatting

- Formatting is StyLua's job, not yours. Run `make format` before committing
- 120 column width, 2 space indent, double quotes, Unix line endings (`stylua.toml`)
- `make test` must pass. `make docs` must be run if you touched anything in `doc/`

## 2. Comments

**The rule: comment the *why*, never the *what*. Default to no comment.**

Read the code around you before you write one. `lua/codecompanion/interactions/chat/parser.lua` is 216 lines and carries 4 inline comments. `lua/codecompanion/utils/files.lua` is 546 lines and carries 9. That is the density to aim for.

Names and control flow carry the narrative. A comment earns its place only when an experienced reader would be confused without it.

**Delete a comment that restates the code:**

```lua
-- ❌ The name already says this
-- Clear the modified flag
self.modified = false

-- ❌ Explains what any Lua reader can see
-- Loop over the messages
for _, message in ipairs(messages) do
```

**Delete a comment that explains a self-evident guard:**

```lua
-- ❌
-- Return early if there's no buffer
if not bufnr then
  return
end
```

**Keep a comment that records a constraint the code cannot show:**

```lua
-- ✅ A Tree-sitter indexing quirk the reader would otherwise trip on
-- Account for the two YAML lines and the fact Tree-sitter is 0-indexed
end_line = vim.tbl_count(adapter.schema) + 2 - 1

-- ✅ Records a deliberate limitation
-- NOTE: Not handling token tables yet
```

**Single line, always.** If your reasoning needs a paragraph, it belongs in the commit message, the PR description, or an issue. Not in the source.

```lua
-- ❌ Five lines of rationale above a test helper
---Record what the parser reports through `log:warn`
---
---That handler is registered at `vim.log.levels.WARN`, so a warning also reaches
---`vim.notify`. The offending fence is never rewritten and so stays broken for the
---rest of the conversation, which is why a given buffer must be reported once
---rather than on every submit.
local function spy_on_warnings()

-- ✅
---Capture the warnings the parser emits
local function capture_warnings()
```

**Don't add banner or section-divider comments** to new files, and don't add a prose header block explaining the bug a file was written for. The tests themselves are the record.

**Commented-out code does not get merged.** Delete it.

## 3. Naming

- `snake_case` for files, functions, locals, and table keys
- `PascalCase` for classes and LuaCATS type names
- `SCREAMING_SNAKE_CASE` only for module-level constant tables and values, never for a local inside a function
- `_leading_underscore` for private functions

**Names must be explicit and domain-specific.** Write `pattern` not `pat`, `should_include` not `include_ok`. Avoid generic placeholder names like `ctx`, `data`, `obj`, `tmp`, `res` - reach for the domain word instead: `permission`, `request`, `source`, `adapter`, `chat`.

```lua
-- ❌ Vague - after what? measured how?
local function recover_headers(chat, root, after)

-- ✅ Says what the number is
local function recover_headers(chat, root, from_row)
```

**Functions are named with a verb.** A past participle or a bare noun reads as a value, not a call.

```lua
-- ❌ Reads like a variable
local function extracted()
local function chat_with(response, lines)

-- ✅
local function get_extracted_message()
local function add_response(response, lines)
```

**Boolean-returning helpers read as a question or a state:** `has_user_messages`, `is_visible`, `should_include`. Don't invent poetic predicates - `hidden_by_open_fence` is cleverer than it is clear; `is_inside_unclosed_fence` is not.

## 4. Functions and type annotations

- **Keep functions under 50 lines.** If it's longer, it's doing too much
- **No module-level globals.** Use module-local state

### Take an `opts` table, not a list of positional arguments

Positional parameters don't scale. Adding one means touching the signature, every call site, and every annotation. An `opts` table absorbs the new parameter in a single place, and call sites that don't care about it stay as they are.

The shape used throughout the codebase is one positional argument for the subject the function acts on, and an `opts` table for everything else - `Chat:add_message(data, opts)`, `Client:send(payload, opts)`, `M.get_settings_key(chat, opts)`. Where there is no natural subject, `opts` is the only parameter.

```lua
-- ❌ Three positionals, and a fourth means editing every caller
function add_header(name, start_from, contents)

-- ✅
---@param opts? { name?: string, start_from?: number, contents?: string[] }
function add_header(opts)
  opts = opts or {}
```

Normalise an optional table on the first line with `opts = opts or {}`, or with `vim.tbl_extend("force", opts or {}, { ... })` when you're layering defaults over it. Annotate the shape inline on the `@param` - `---@param opts? { auto_submit?: boolean }` - so callers can see the keys without opening the function.

LuaCATS annotations are expected on public APIs.

**A function description is exactly one line.** No multi-paragraph rationale, no usage examples, no "why we cache this" essays. If you can't summarise the function in one line, split the function.

**Drop the description entirely when the name already says it,** and drop annotations that carry no information.

```lua
-- ❌ Description restates the name; the return annotation says nothing
---Get the chat buffer number
---@param chat CodeCompanion.Chat
---@return nil
local function get_bufnr(chat)

-- ✅
---@param chat CodeCompanion.Chat
---@return number
local function get_bufnr(chat)
```

Don't annotate params with inline explanations - if a param needs explaining, rename it.

## 5. Tests

Tests use [Mini.Test](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-test.md) with child Neovim processes. Read an existing test file before writing one - `tests/adapters/test_openai.lua` and `tests/interactions/chat/test_chat.lua` are good models. There are roughly 800 tests and they act as a second source of documentation.

**File layout mirrors the source tree.** `lua/codecompanion/interactions/chat/parser.lua` is tested by `tests/interactions/chat/test_parser.lua`. Don't invent a suffix like `test_parser_resilience.lua` for a subset of a module's behaviour - add cases to the module's existing test file.

**Test names follow the existing suite.** The pattern is `T["<Subject>"]["<what it does>"]`, where the subject is the capitalised module or feature (`T["Chat"]`, `T["Context"]`, `T["Keymaps"]`) and the case name completes the sentence "it ...". Keep them short and behavioural.

```lua
-- ✅ Matches the suite
T["Chat"]["can load default tools"] = function()
T["Chat"]["system prompt is added first"] = function()
T["Context"]["Cannot be added twice with the same id"] = function()

-- ❌ Narrative prose that reads nothing like its neighbours
T["Parser"]["an unterminated fence does not eat the next prompt"] = function()
T["Parser"]["a balanced response leaves the prompt extractable"] = function()
```

**Test what the change actually does.** Comprehensive-looking tests that never exercise the edge case are worse than no tests. Don't test a schema mirroring itself, and don't test that a shared utility passes its errors through.

**Don't write tests for chat buffer cursor position, scrolling, or folds.** These are verified by hand in real use. Ask first if you think a case is warranted.

**Use an LLM for the feature or the tests. Not both.**

## 6. Error handling and defensive code

- Wrap fallible calls in `pcall`, log with `log:error()`, return `nil` on failure
- **Don't add defensive guards for conditions that cannot occur.** Validating a param that every caller in the repo already supplies is noise, and it hides the real contract
- Don't add a fallback path "just in case". If the primary path can fail, show the failing case in a test; if it can't, delete the fallback

## 7. Files and paths

Use the helpers in `lua/codecompanion/utils/files.lua` for anything touching the filesystem, and join paths with `vim.fs.joinpath` rather than string concatenation or hardcoded separators.

## 8. Scope

- Do what the PR says it does, nothing more
- Don't create new files unless there is no reasonable place for the code to live. Prefer editing an existing file
- Don't add documentation files that weren't asked for
- Don't reformat, rename, or "tidy" code your change doesn't touch - it buries the actual diff

## 9. Language

Plain English, in code, comments, commit messages and PR descriptions. Say what actually happens rather than reaching for jargon: "returns unchanged", "does nothing", "skipped because it was already handled" - not "no-op". Never use an em dash; use a plain dash.
