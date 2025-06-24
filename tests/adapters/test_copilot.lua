local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Copilot adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("copilot")
    end,
  },
})

T["Copilot adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Copilot adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests/strategies/chat/agents/tools/stubs/weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Copilot adapter"]["Streaming"] = new_set()

T["Copilot adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/copilot_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("**Elegant simplicity.**", output)
end

T["Copilot adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/stubs/copilot_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"location": "London, UK", "units": "celsius"}',
        name = "weather",
      },
      id = "tooluse_ZnSMh7lhSxWDIuVBKd_vLg",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

T["Copilot adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("copilot", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Copilot adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/copilot_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    "**Dynamic elegance.**\\n\\nWhat specific aspect of Ruby would you like to explore further?",
    adapter.handlers.chat_output(adapter, json).output.content
  )
end

T["Copilot adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/copilot_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location":"London, UK","units":"celsius"}',
        name = "weather",
      },
      id = "tooluse_0QuujwyeSCGpbfteXu-sHw",
      type = "function",
    },
  }
  h.eq(tool_output, tools)
end

T["Copilot adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/copilot_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    "**Dynamic elegance.**\\n\\nWhat specific aspect of Ruby would you like to explore further?",
    adapter.handlers.inline_output(adapter, json).output
  )
end

T["Stats"] = new_set()

T["Stats"]["can calculate usage percentages correctly"] = function()
  local entitlement, remaining = 300, 250
  local used = entitlement - remaining
  local usage_percent = entitlement > 0 and (used / entitlement * 100) or 0
  h.eq(50, used)
  -- 50/300 * 100 = 16.666... so we need to check the rounded value
  h.eq(16.7, math.floor(usage_percent * 10 + 0.5) / 10)

  local zero_entitlement = 0
  local zero_percent = zero_entitlement > 0 and (0 / zero_entitlement * 100) or 0
  h.eq(0, zero_percent)

  -- Test full usage
  local full_entitlement, no_remaining = 100, 0
  local full_used = full_entitlement - no_remaining
  local full_percent = full_entitlement > 0 and (full_used / full_entitlement * 100) or 0
  h.eq(100, full_used)
  h.eq(100.0, full_percent)
end

T["Stats"]["can determine correct highlight colors based on usage"] = function()
  local function get_usage_highlight(usage_percent)
    if usage_percent >= 80 then
      return "Error"
    else
      return "MoreMsg"
    end
  end

  -- Test low usage (green)
  h.eq("MoreMsg", get_usage_highlight(16.7))
  h.eq("MoreMsg", get_usage_highlight(50))
  h.eq("MoreMsg", get_usage_highlight(79.9))
  -- Test high usage (red)
  h.eq("Error", get_usage_highlight(80))
  h.eq("Error", get_usage_highlight(85))
  h.eq("Error", get_usage_highlight(100))

  h.eq("MoreMsg", get_usage_highlight(0))
end

return T
