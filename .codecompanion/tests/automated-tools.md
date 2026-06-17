# Tool Testing Script

Enables CodeCompanion to run actual tools with an adapter and a model to create a real-world testing workflow. This saves the user from having to manually orchestrate a test harness for each tool and test each time.

## Structure

```
tests/scripts/tool_testing/
  run_tests.lua          # entry point (nvim -l)
  test.sh                # shell wrapper (recommended)
  config.lua             # shape/defaults only, no enabled adapters (checked in)
  config.local.lua       # user's adapter matrix (gitignored)
  config.local.lua.example
  .env                   # API keys (gitignored)
  .env.example
  scenarios/
    insert_edit_into_file/   # 13 scenarios covering key failure modes
```

@./tests/scripts/tool_testing/README.md
@./tests/scripts/tool_testing/config.lua
@./tests/scripts/tool_testing/config.local.lua
@./tests/scripts/tool_testing/run_tests.lua
@./tests/scripts/tool_testing/setup_tests.lua
@./tests/scripts/tool_testing/test.sh

## Key design decisions

- **Real chat buffer, real submit path** — `codecompanion.chat({ params = { adapter, model }, yolo_mode = true, hidden = true })`. No HTTP mocking.
- **`yolo_mode` on the chat** — `Chat.new()` calls `approvals:toggle_yolo_mode(self.bufnr)` when `args.yolo_mode = true`. `Chat:close()` calls `approvals:reset(self.bufnr)` (also fixes bufnr recycling leak for all chats).
- **`chat:submit({ auto_submit = true })`** — required when adding messages programmatically. Without `auto_submit = true`, submit reads the buffer (empty), adds a blank_prompt on top of the real message, and the model sees a blank instruction.
- **`on_completed` callback** — used instead of polling `current_request`. The old polling loop's `else` branch fired immediately when `current_request` was nil (before the async HTTP request was registered), completing the test before the model had responded.
- **`msg.role == "llm"`** — CodeCompanion stores LLM messages with role `"llm"`, not `"assistant"`. Checking for `"assistant"` meant tool_calls were never captured, causing `tools_required` to always fail.
- **Scenario DSL** — `{ name, description, tools, tools_required?, setup, prompt, test, cleanup }`. One file per scenario under `scenarios/<tool>/`; runner globs them.
- **`test(ctx, run)`** — called after the chat completes. Returns `(bool, string|nil)`. Can execute the output file, diff against expected content, or inspect `run.tool_calls` / `run.response_content` directly.
- **`tools_required`** — runner fails scenario before `test` if any listed tool was never called.
- **Tool call count** — shown in result line (`1 call`, `3 calls`). Captures retries; a model that self-corrected shows >1.
- **CSV output** — `--csv` flag appends rows. Accumulates across runs for cross-model comparison.
- **Secrets in `.env`** — loaded by `test.sh` (shell `source`) and `run_tests.lua` (`vim.fn.setenv`). `config.local.lua` holds the adapter matrix only, no keys.
- **deps/ for plenary** — `setup_runtimepath()` prefers `deps/plenary.nvim` (same as `make test`) over lazy.nvim data dir.
- **Concurrency** — up to `config.concurrency.max_concurrent` scenarios run at once (default 5). When a slot frees, the next queued scenario starts immediately.
- **Paired output** — `RUN` line is printed at finalize time, immediately followed by the `PASS`/`FAIL`/`ERROR` line. No interleaving between the two.
- **Colourisation** — all ANSI codes are applied in `test.sh` via awk (Lua outputs plain text). Nerd Font icons for PASS/FAIL/ERROR are injected there too.
- **Success rate thresholds** — configurable in `config.thresholds`: `error_below` (red) and `warn_below` (amber); green at or above `warn_below`.

## Scenario coverage (insert_edit_into_file)

13 scenarios. Covers: simple file edit, tab-indented Python, replace-all, empty `new_string` deletion, top-of-file insertion, adjacent edits, CRLF line endings, Unicode content, JSON editing, trailing whitespace, targeted edit, real-world Python, real-world Ruby.

## Running

```bash
make deps  # first time only
./tests/scripts/tool_testing/test.sh run --adapter=anthropic
./tests/scripts/tool_testing/test.sh run --adapter=anthropic --verbose
./tests/scripts/tool_testing/test.sh run --scenario="CRLF line endings"
./tests/scripts/tool_testing/test.sh run --scenario="CRLF line endings" --adapter=openai
./tests/scripts/tool_testing/test.sh run --tool=insert_edit_into_file
./tests/scripts/tool_testing/test.sh run --csv
./tests/scripts/tool_testing/test.sh results
./tests/scripts/tool_testing/test.sh failures
```

## Baseline goal

Run the full harness against `insert_edit_into_file` before the new `edit_file` tool lands, to establish a per-failure-mode pass rate. Then compare new vs old once Stage 1 of the rewrite is done.

