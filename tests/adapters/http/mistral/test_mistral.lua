local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

local mistral_models = {
  ["mistral-medium-2505"] = {
    formatted_name = "mistral-medium-2505",
    opts = {
      has_vision = true,
      can_use_tools = true,
    },
  },
  ["mistral-large-latest"] = {
    formatted_name = "mistral-large-latest",
    opts = {
      has_vision = true,
      can_use_tools = true,
    },
  },
  ["ministral-8b-latest"] = {
    formatted_name = "ministral-8b-2410",
    opts = {
      has_vision = false,
      can_use_tools = true,
    },
  },
}

local _original_choices

T["Mistral adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("mistral")

      local get_models = require("codecompanion.adapters.http.mistral.get_models")
      _original_choices = get_models.choices
      get_models.choices = function(adapter_arg, opts)
        return mistral_models
      end
    end,

    post_case = function()
      if _original_choices then
        local get_models = require("codecompanion.adapters.http.mistral.get_models")
        get_models.choices = _original_choices
        _original_choices = nil
      end
    end,
  },
})

T["Mistral adapter"]["it can form messages"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Mistral adapter"]["Streaming"] = new_set()

T["Mistral adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/mistral_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Dynamic Language", output)
end

T["Mistral adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("mistral", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Mistral adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/mistral_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic Language", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Mistral adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/mistral_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic Language", adapter.handlers.inline_output(adapter, json).output)
end

return T
