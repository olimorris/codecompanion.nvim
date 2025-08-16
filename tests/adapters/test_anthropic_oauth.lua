local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Anthropic OAuth adapter"] = new_set({
  hooks = {
    pre_case = function()
      local codecompanion = require("codecompanion")
      adapter = require("codecompanion.adapters").resolve("anthropic_oauth")
    end,
  },
})

T["Anthropic OAuth adapter"]["inherits from Anthropic adapter"] = function()
  h.eq("anthropic_oauth", adapter.name)
  h.eq("Anthropic (OAuth)", adapter.formatted_name)
  h.eq("https://api.anthropic.com/v1/messages", adapter.url)

  -- Should have the same features as the base Anthropic adapter
  h.eq(true, adapter.features.text)
  h.eq(true, adapter.features.tokens)
  h.eq(true, adapter.opts.stream)
  h.eq(true, adapter.opts.tools)
  h.eq(true, adapter.opts.vision)
end

T["Anthropic OAuth adapter"]["has OAuth-specific configuration"] = function()
  -- Should use OAuth token instead of API key
  h.eq("function", type(adapter.env.api_key))

  -- Should have authorization header instead of x-api-key
  h.eq("Bearer ${api_key}", adapter.headers.authorization)
  h.eq(nil, adapter.headers["x-api-key"])
end

T["Anthropic OAuth adapter"]["form_messages"] = new_set()

T["Anthropic OAuth adapter"]["form_messages"]["works the same as base adapter"] = function()
  local messages = {
    { content = "Hello", role = "system" },
    { content = "What can you do?!", role = "user" },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  h.eq("Hello", output.system[1].text)
  h.eq({
    {
      content = {
        {
          type = "text",
          text = "What can you do?!",
        },
      },
      role = "user",
    },
  }, output.messages)
end

T["Anthropic OAuth adapter"]["schema"] = function()
  -- Should inherit the same schema structure as the base adapter
  h.eq("enum", adapter.schema.model.type)
  h.eq("claude-sonnet-4-20250514", adapter.schema.model.default)
  h.eq("number", adapter.schema.temperature.type)
  h.eq(0, adapter.schema.temperature.default)
end

T["Anthropic OAuth adapter"]["handlers"] = function()
  -- Should have all the same handlers as the base adapter
  h.eq("function", type(adapter.handlers.form_messages))
  h.eq("function", type(adapter.handlers.form_parameters))
  h.eq("function", type(adapter.handlers.chat_output))
  h.eq("function", type(adapter.handlers.inline_output))
  h.eq("function", type(adapter.handlers.tokens))

  -- Should have OAuth-specific setup handler
  h.eq("function", type(adapter.handlers.setup))
end

return T
