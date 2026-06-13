-- Configuration for automated tool testing
-- Copy this to config.local.lua and add API keys - calling test.sh setup will create that file
-- Scenarios live in scenarios/*.lua — add new scenarios by dropping a file there

local M = {}

-- Custom Adapter Definitions
-- Define custom adapters that aren't built into CodeCompanion
-- These will be registered before tests run
M.adapter_definitions = {
  -- Example: OpenRouter adapter
  -- openrouter = {
  --   extends = "openai", -- Base adapter to extend from
  --   url = "https://openrouter.ai/api/v1/chat/completions",
  --   env = {
  --     api_key = "cmd:api-pass openrouter", -- or function() return get_api_key("openrouter") end
  --   },
  --   headers = {
  --     ["HTTP-Referer"] = "https://github.com/codecompanion-test",
  --     ["X-Title"] = "CodeCompanion Tool Testing",
  --   },
  --   schema = {
  --     model = {
  --       default = "openai/gpt-oss-120b",
  --     },
  --   },
  -- },
}

-- Adapter matrix — define in config.local.lua, not here
-- Example entry:
-- { name = "anthropic", enabled = true, models = { "claude-haiku-4-5" }, timeout = 30000 }
M.adapters = {}

-- Output configuration
M.output = {
  csv_file = nil, -- Path to append CSV results to across runs (e.g. set in config.local.lua)
  results_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "codecompanion", "tool_testing"),
  save_logs = true,
  verbose = true,
}

-- Concurrency settings
M.concurrency = {
  max_concurrent = 5, -- Maximum concurrent tests
  parallel = true, -- Run adapters in parallel (true) or sequentially (false)
}

-- Success rate colour thresholds (percentage)
M.thresholds = {
  error_below = 50, -- red below this value
  warn_below = 80, -- amber below this value, green at or above
}

return M
