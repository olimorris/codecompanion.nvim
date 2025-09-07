local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Gemini CLI adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("gemini_cli")
    end,
  },
})

T["Gemini CLI adapter"]["only sends fresh user messages to the LLM"] = function()
  local messages = {
    {
      _meta = {
        sent = true,
      },
      content = "Can you explain Ruby in two words?",
      role = "user",
    },
    {
      _meta = {},
      content = "Dynamic. Elegant",
      role = "llm",
    },
    {
      _meta = {},
      content = "Awesome! Thanks",
      role = "user",
    },
  }

  local output = {
    {
      text = "Awesome! Thanks",
      type = "text",
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Gemini CLI adapter"]["can form multiple messages to be sent"] = function()
  local messages = {
    {
      _meta = {},
      content = "Can you explain Ruby in two words?",
      role = "user",
    },
    {
      _meta = {},
      content = "Make it snappy",
      role = "user",
    },
  }

  local output = {
    {
      text = "Can you explain Ruby in two words?",
      type = "text",
    },
    {
      text = "Make it snappy",
      type = "text",
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

return T
