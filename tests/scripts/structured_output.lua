--[[
Manual test script for structured output
NOTE: GENERATED ENTIRELY BY AUGMENT CODE FOR TESTING PURPOSES ONLY

Usage: With CodeCompanion loaded in Neovim:
  :source %

What it does:
  1. Builds a Background interaction against an adapter
  2. Issues a sync request with a `structured_output` schema in opts
  3. Prints the raw content, the decoded table, and any error

Expected: the LLM returns valid JSON matching the schema (location,
temperature, conditions). If the adapter lacks a structured-output
handler the request short-circuits and an error is printed.
--]]

local Background = require("codecompanion.interactions.background")

local adapter_config = {
  anthropic = require("codecompanion.adapters").extend("anthropic", {
    env = {
      api_key = "cmd:op read op://personal/Anthropic_API/credential --no-newline",
    },
  }),
  copilot = "copilot",
  gemini = require("codecompanion.adapters").extend("gemini", {
    env = {
      api_key = "cmd:op read op://personal/Gemini_API/credential --no-newline",
    },
  }),
  gemini_interactions = require("codecompanion.adapters").extend("gemini_interactions", {
    env = {
      api_key = "cmd:op read op://personal/Gemini_API/credential --no-newline",
    },
  }),
  mistral = require("codecompanion.adapters").extend("mistral", {
    env = {
      api_key = "cmd:op read op://personal/Mistral_API/credential --no-newline",
    },
  }),
  openai = require("codecompanion.adapters").extend("openai", {
    env = {
      api_key = "cmd:op read op://personal/OpenAI_API/credential --no-newline",
    },
  }),
  openai_responses = require("codecompanion.adapters").extend("openai_responses", {
    env = {
      api_key = "cmd:op read op://personal/OpenAI_API/credential --no-newline",
    },
  }),
  openrouter = require("codecompanion.adapters").extend("openrouter", {
    env = {
      api_key = "cmd:op read op://personal/OpenRouter_API/credential --no-newline",
    },
  }),
}

local adapter_name = "gemini_interactions"
local adapter = adapter_config[adapter_name]

local structured_output = {
  name = "weather",
  strict = true,
  schema = {
    type = "object",
    properties = {
      location = { type = "string", description = "City or location name" },
      temperature = { type = "number", description = "Temperature in Celsius" },
      conditions = { type = "string", description = "Weather conditions description" },
    },
    required = { "location", "temperature", "conditions" },
    additionalProperties = false,
  },
}

local messages = {
  {
    role = "system",
    content = "You are a weather reporter. Respond with concise, plausible data. You can make this up. Don't use live data",
  },
  {
    role = "user",
    content = "What is the weather in Paris right now?",
  },
}

local background = Background.new({ adapter = adapter })

local result, err = background:ask(messages, {
  method = "sync",
  silent = true,
  structured_output = structured_output,
})

print("---- Structured Output Test ----")

if err then
  print("ERROR: " .. vim.inspect(err))
  return
end

if not result then
  print("No result returned")
  return
end

print("Status: " .. tostring(result.status))
print("Adapter: " .. tostring(background.adapter.formatted_name))
print("Model: " .. tostring(background.adapter.schema.model.default))
print("Raw content:")
print(result.output and result.output.content or "<nil>")

if result.output and result.output.content then
  local ok, decoded = pcall(vim.json.decode, result.output.content)
  if ok then
    print("Decoded:")
    print(vim.inspect(decoded))
  else
    print("Failed to decode JSON: " .. tostring(decoded))
  end
end
