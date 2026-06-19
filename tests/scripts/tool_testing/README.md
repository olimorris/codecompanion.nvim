# CodeCompanion Tool Testing

Runs CodeCompanion tools against real LLM adapters to catch regressions that unit tests can't — things that only break when a model's output is wired through the full tool orchestrator.

Each test drives a real chat buffer, submits a prompt, waits for the tool to execute, then validates the result.

---

## Setup

### 1. Install dependencies

```bash
make deps
```

This clones `plenary.nvim` and `nvim-treesitter` into `deps/`, which the test runner uses.

### 2. Add your API keys

```bash
cp tests/scripts/tool_testing/.env.example tests/scripts/tool_testing/.env
```

Edit `.env` and fill in the keys for the adapters you want to test. The file is gitignored.

### 3. Set your adapter matrix

```bash
cp tests/scripts/tool_testing/config.local.lua.example tests/scripts/tool_testing/config.local.lua
```

Edit `config.local.lua` to list the adapters and models you want to run. This file is gitignored.

---

## Running

All commands are run from the repo root.

```bash
# Run all enabled adapters across all tools
./tests/scripts/tool_testing/test.sh run

# Single adapter
./tests/scripts/tool_testing/test.sh run --adapter=anthropic

# Single tool (runs all scenarios in scenarios/insert_edit_into_file/)
./tests/scripts/tool_testing/test.sh run --tool=insert_edit_into_file

# Single adapter + single tool
./tests/scripts/tool_testing/test.sh run --adapter=anthropic --tool=insert_edit_into_file

# Single adapter, single model
./tests/scripts/tool_testing/test.sh run --adapter=anthropic --model=claude-haiku-4-5

# Single scenario
./tests/scripts/tool_testing/test.sh run --scenario="Simple file edit"

# Verbose (shows tool calls, validation details, result file paths)
./tests/scripts/tool_testing/test.sh run --adapter=anthropic --verbose

# Append results to CSV (accumulates across runs for comparison)
./tests/scripts/tool_testing/test.sh run --csv

# Write per-run JSON and summary JSON to disk (off by default)
./tests/scripts/tool_testing/test.sh run --log

# Add delay between scenarios (useful for rate-limited providers)
./tests/scripts/tool_testing/test.sh run --adapter=gemini --delay=2000

# Repeat each scenario n times (useful for measuring consistency across runs)
./tests/scripts/tool_testing/test.sh run --repeat=5
./tests/scripts/tool_testing/test.sh run --scenario="Simple file edit" --repeat=10 --csv
```

### Inspecting results

```bash
# Summary of the latest run
./tests/scripts/tool_testing/test.sh results

# Details of failures only
./tests/scripts/tool_testing/test.sh failures

# Remove old result files
./tests/scripts/tool_testing/test.sh clean
```

JSON results are saved to `~/.local/share/nvim/codecompanion/tool_testing/`. The CSV (when `--csv` is used) defaults to `results.csv` in that same directory, or a custom path set via `config.output.csv_file`.

---

## Configuration

### `config.lua`

Checked in. Defines defaults (output directory, timeouts, concurrency). **No adapters are enabled here** — it is shape only.

### `config.local.lua`

Gitignored. Your personal adapter matrix. Merged on top of `config.lua` at runtime.

```lua
local M = {}

M.adapters = {
  {
    enabled = true,
    models = { "claude-haiku-4-5", "claude-sonnet-4-5" },
    name = "anthropic",
    timeout = 30000,
  },
  {
    enabled = true,
    models = { "gpt-4.1", "gpt-4.1-mini" },
    name = "openai",
    timeout = 30000,
  },
}

-- Optional: fix the CSV path so --csv always writes to the same file
-- M.output = {
--   csv_file = vim.fs.joinpath(vim.fn.stdpath("data"), "codecompanion", "tool_testing", "results.csv"),
-- }

return M
```

### `.env`

Gitignored. API keys, loaded before config so adapter env vars are populated.

```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

### Custom adapters

For providers not built into CodeCompanion (OpenRouter, xAI, etc.), define them in `config.local.lua` under `adapter_definitions`:

```lua
M.adapter_definitions = {
  openrouter = {
    extends = "openai",
    url = "https://openrouter.ai/api/v1/chat/completions",
    env = { api_key = os.getenv("OPENROUTER_API_KEY") },
    headers = {
      ["HTTP-Referer"] = "https://github.com/olimorris/codecompanion.nvim",
      ["X-Title"] = "CodeCompanion Tool Testing",
    },
    schema = { model = { default = "qwen/qwen3-coder" } },
  },
}

M.adapters = {
  {
    enabled = true,
    models = { "qwen/qwen3-coder", "moonshotai/kimi-k2" },
    name = "openrouter",
    timeout = 30000,
  },
}
```

---

## Adding scenarios

Scenarios are organised by tool under `scenarios/<tool_name>/`. Drop a `.lua` file into the relevant subfolder and the runner picks it up automatically — no registration needed.

```
scenarios/
  insert_edit_into_file/
    simple_file_edit.lua
    multiple_edits.lua
    tool_group.lua
  read_file/
    simple_read.lua
  delete_file/
    simple_delete.lua
```

Each scenario returns a table with four functions. The recommended pattern is to declare `CONTENT` and `EXPECTED` at the top of the file so both are visible at a glance:

````lua
-- scenarios/insert_edit_into_file/my_scenario.lua
local CONTENT = {
  "local M = {}",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "function M.greet()",
  '  return "Hello"',
  "end",
  "",
  "return M",
}

return {
  name = "My scenario",
  description = "What this tests",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },  -- fail if tool was never called

  setup = function()
    local test_file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      "Use @{insert_edit_into_file} to add a `greet` function to `%s`.\n\n```lua\n%s\n```\n\nDo not ask for permission — call the tool directly.",
      ctx.test_file,
      table.concat(CONTENT, "\n")
    )
  end,

  -- ctx = whatever setup() returned
  -- run = { tool_calls = [...], response_content = "..." }
  validate = function(ctx, _run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then actual[#actual] = nil end
    local ok = vim.deep_equal(actual, EXPECTED)
    return ok, { actual = table.concat(actual, "\n"), expected = table.concat(EXPECTED, "\n") }
  end,

  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,
}
````

`tools_required` is optional. When set, the runner fails the scenario before calling `validate` if any listed tool was never called — catches the case where the model writes the right text but skips the tool entirely.

The `run.tool_calls` array records every tool call made during the exchange, including retries. The call count is shown in the result line (`1 call`, `3 calls`) so you can see which models self-corrected and how many attempts they needed.

For tools that don't produce file artifacts (e.g. `read_file`, `grep_search`), verify via `run.tool_calls` and `run.response_content` instead:

```lua
validate = function(ctx, run)
  local called = false
  for _, call in ipairs(run.tool_calls) do
    if call.name == "read_file" and call.arguments:find(ctx.test_file, 1, true) then
      called = true
    end
  end
  local surfaced = run.response_content:find("expected-token", 1, true) ~= nil
  return called and surfaced, { called = called, surfaced = surfaced }
end
```

---

## Logging to disk

Pass `--log` to save per-run JSON files with full details of the chat message history and token use.

## CSV output

Pass `--csv` to append a row per result to a CSV file. Runs accumulate, making it easy to compare models across multiple sessions:

```
run_at,adapter,model,scenario,result,duration_s,tool_calls,error
2026-06-10 12:11:42,anthropic,claude-haiku-4-5,Simple file edit,pass,5.89,1,
2026-06-10 12:11:48,anthropic,claude-sonnet-4-5,Simple file edit,pass,4.21,1,
2026-06-10 12:14:31,copilot,gpt-5-mini,Simple file edit,pass,7.66,2,
```

`tool_calls` is the total number of tool invocations, including retries. A model that needed 3 attempts before getting the edit right will show `3` here.
