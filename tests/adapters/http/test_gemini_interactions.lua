local h = require("tests.helpers")
local tags = require("codecompanion.interactions.shared.tags")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Gemini Interactions adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("gemini_interactions")
    end,
  },
})

T["Gemini Interactions adapter"]["can form messages to be sent to the API"] = function()
  local messages = {
    {
      content = "Follow the user's request",
      role = "system",
    },
    {
      content = "Respond in code",
      role = "system",
    },
    {
      content = "Explain Ruby in two words",
      role = "user",
    },
  }

  local output = {
    input = {
      {
        type = "user_input",
        content = "Explain Ruby in two words",
      },
    },
    system_instruction = "Follow the user's request\n\nRespond in code",
  }

  h.eq(output, adapter.handlers.request.build_messages(adapter, messages))
end

T["Gemini Interactions adapter"]["can form messages without system prompt"] = function()
  local messages = {
    {
      content = "hello",
      role = "user",
    },
    {
      content = "Hi, how can I help?",
      role = "model",
    },
  }

  local output = {
    input = {
      {
        type = "user_input",
        content = "hello",
      },
      {
        type = "model_output",
        content = { { type = "text", text = "Hi, how can I help?" } },
      },
    },
  }

  h.eq(output, adapter.handlers.request.build_messages(adapter, messages))
end

T["Gemini Interactions adapter"]["can form messages with tool calls and responses"] = function()
  local messages = {
    {
      content = "What's the weather?",
      role = "user",
    },
    {
      role = "model",
      tools = {
        calls = {
          {
            _index = 1,
            id = "call_1",
            signature = "Ev0BCvoBAb4",
            type = "function",
            ["function"] = {
              arguments = '{"location":"London"}',
              name = "weather",
            },
          },
        },
      },
    },
    {
      content = '{"temperature": 20}',
      role = "tool",
      tools = {
        call_id = "call_1",
        name = "weather",
      },
    },
  }

  local output = {
    input = {
      { type = "user_input", content = "What's the weather?" },
      {
        type = "function_call",
        id = "call_1",
        name = "weather",
        arguments = { location = "London" },
        signature = "Ev0BCvoBAb4",
      },
      {
        type = "function_result",
        name = "weather",
        call_id = "call_1",
        result = { { type = "text", text = '{"temperature": 20}' } },
      },
    },
  }

  h.eq(output, adapter.handlers.request.build_messages(adapter, messages))
end

T["Gemini Interactions adapter"]["can form messages with tool call text content"] = function()
  local messages = {
    {
      content = "What's the weather?",
      role = "user",
    },
    {
      content = "I'll check the weather for you.",
      role = "model",
      tools = {
        calls = {
          {
            _index = 1,
            id = "call_1",
            type = "function",
            ["function"] = { arguments = '{"location":"London"}', name = "weather" },
          },
        },
      },
    },
  }

  local output = adapter.handlers.request.build_messages(adapter, messages)

  h.eq(3, #output.input)
  h.eq("model_output", output.input[2].type)
  h.eq("I'll check the weather for you.", output.input[2].content[1].text)
  h.eq("function_call", output.input[3].type)
  h.eq("weather", output.input[3].name)
  h.eq({ location = "London" }, output.input[3].arguments)
end

T["Gemini Interactions adapter"]["can form messages with reasoning"] = function()
  local messages = {
    {
      content = "What's 2+2?",
      role = "user",
    },
    {
      content = "4",
      reasoning = { content = "Let me compute", signature = "sig-abc" },
      role = "model",
    },
  }

  local output = adapter.handlers.request.build_messages(adapter, messages)

  h.eq(3, #output.input)
  h.eq({
    type = "thought",
    signature = "sig-abc",
    summary = { { type = "text", text = "Let me compute" } },
  }, output.input[2])
  h.eq({
    type = "model_output",
    content = { { type = "text", text = "4" } },
  }, output.input[3])
end

T["Gemini Interactions adapter"]["can form messages with an image and following text"] = function()
  local messages = {
    {
      content = "base64encodedimage",
      role = "user",
      context = { mimetype = "image/jpeg" },
      _meta = { tag = tags.IMAGE },
    },
    {
      content = "Compare this local image and this remote audio file.",
      role = "user",
    },
  }

  local output = adapter.handlers.request.build_messages(adapter, messages)

  h.eq(1, #output.input)
  h.eq("user_input", output.input[1].type)
  h.eq({
    { type = "image", data = "base64encodedimage", mime_type = "image/jpeg" },
    { type = "text", text = "Compare this local image and this remote audio file." },
  }, output.input[1].content)
end

T["Gemini Interactions adapter"]["can form messages with a PDF document and following text"] = function()
  local messages = {
    {
      content = "base64encodedpdf",
      role = "user",
      context = { mimetype = "application/pdf", path = "report.pdf" },
      _meta = { tag = tags.DOCUMENT, filetype = "pdf" },
    },
    {
      content = "Summarize this document",
      role = "user",
    },
  }

  local output = adapter.handlers.request.build_messages(adapter, messages)

  h.eq(1, #output.input)
  h.eq("user_input", output.input[1].type)
  h.eq({
    { type = "document", data = "base64encodedpdf", mime_type = "application/pdf" },
    { type = "text", text = "Summarize this document" },
  }, output.input[1].content)
end

T["Gemini Interactions adapter"]["only PDFs are converted into document blocks"] = function()
  local messages = {
    {
      content = "base64encodeddocx",
      role = "user",
      context = { mimetype = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
      _meta = { tag = tags.DOCUMENT, filetype = "docx" },
    },
  }

  local output = adapter.handlers.request.build_messages(adapter, messages)

  h.eq("user_input", output.input[1].type)
  h.eq("base64encodeddocx", output.input[1].content)
end

T["Gemini Interactions adapter"]["can form tools to be sent to the API"] = function()
  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }

  local output = adapter.handlers.request.build_tools(adapter, tools)

  h.eq(1, #output.tools)
  local decl = output.tools[1]
  h.eq("function", decl.type)
  h.eq("weather", decl.name)
  h.eq(weather["function"].description, decl.description)
  h.eq(weather["function"].parameters.type, decl.parameters.type)
  h.eq(weather["function"].parameters.properties, decl.parameters.properties)
  h.eq(weather["function"].parameters.required, decl.parameters.required)

  -- Gemini does not support additionalProperties or strict
  h.eq(nil, decl.parameters.additionalProperties)
  h.eq(nil, decl.parameters.strict)
end

T["Gemini Interactions adapter"]["can form the built-in google_search tool"] = function()
  local tools = {
    {
      ["<tool>google_search</tool>"] = {
        _meta = { adapter_tool = true },
        description = "Allows the model to search the web via Google Search",
        name = "google_search",
      },
    },
  }

  h.eq({ tools = { { type = "google_search" } } }, adapter.handlers.request.build_tools(adapter, tools))
end

T["Gemini Interactions adapter"]["can form reasoning output from streamed chunks"] = function()
  local input = {
    { content = "Let me " },
    { content = "think about this" },
    { signature = "sig-part-1" },
    { signature = "sig-part-2" },
  }

  h.eq({
    content = "Let me think about this",
    signature = "sig-part-1sig-part-2",
  }, adapter.handlers.request.build_reasoning(adapter, input))
end

T["Gemini Interactions adapter"]["can normalize tool calls via format_calls"] = function()
  local raw_tools = {
    {
      _index = 1,
      args = { location = "London", units = "celsius" },
      id = "call_1",
      name = "weather",
    },
  }

  local formatted = adapter.handlers.tools.format_calls(adapter, raw_tools)

  h.eq(1, #formatted)
  h.eq(1, formatted[1]._index)
  h.eq("function", formatted[1].type)
  h.eq("weather", formatted[1]["function"].name)

  -- arguments should be a JSON string
  local decoded = vim.json.decode(formatted[1]["function"].arguments)
  h.eq("London", decoded.location)
  h.eq("celsius", decoded.units)
end

T["Gemini Interactions adapter"]["can format tool response via format_response"] = function()
  local tool_call = {
    id = "call_123",
    type = "function",
    ["function"] = { arguments = '{"location":"London"}', name = "weather" },
  }

  local result = adapter.handlers.tools.format_response(adapter, tool_call, '{"temperature": 20}')

  h.eq("tool", result.role)
  h.eq("weather", result.tools.name)
  h.eq("call_123", result.tools.call_id)
  h.eq('{"temperature": 20}', result.content)
end

T["Gemini Interactions adapter"]["Streaming"] = new_set()

T["Gemini Interactions adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local reasoning_signature
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.response.parse_chat(adapter, line)
    if chat_output then
      if chat_output.output.content then
        output = output .. chat_output.output.content
      end
      if chat_output.output.reasoning and chat_output.output.reasoning.signature then
        reasoning_signature = (reasoning_signature or "") .. chat_output.output.reasoning.signature
      end
    end
  end

  h.eq("AI works ", output)
  h.eq("EvEFCu4F...", reasoning_signature)
end

T["Gemini Interactions adapter"]["Streaming"]["can process reasoning summaries"] = function()
  local reasoning_content
  local reasoning_signature
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_reasoning_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.response.parse_chat(adapter, line)
    if chat_output and chat_output.output.reasoning then
      if chat_output.output.reasoning.content then
        reasoning_content = (reasoning_content or "") .. chat_output.output.reasoning.content
      end
      if chat_output.output.reasoning.signature then
        reasoning_signature = (reasoning_signature or "") .. chat_output.output.reasoning.signature
      end
    end
  end

  h.expect_starts_with("**Evaluating the clues**", reasoning_content)
  h.expect_starts_with("EpoGCpcGAXLI2nx/...", reasoning_signature)
end

T["Gemini Interactions adapter"]["Streaming"]["can process a streamed tool call"] = function()
  -- Regression test: step.start only ever carries a placeholder `{}` for
  -- arguments; the real arguments arrive later via an `arguments_delta`
  -- step.delta as a JSON string. Thought summaries stream via a
  -- `thought_summary` delta with nested `content.text`, not a flat `text` delta.
  local tools = {}
  local reasoning_content
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_tools_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.response.parse_chat(adapter, line, tools)
    if chat_output and chat_output.output.reasoning and chat_output.output.reasoning.content then
      reasoning_content = (reasoning_content or "") .. chat_output.output.reasoning.content
    end
  end

  h.expect_starts_with("**Analyzing the Command**", reasoning_content)

  h.eq(1, #tools)
  h.eq("run_command", tools[1].name)
  h.eq('{"cmd":"ls -la"}', tools[1].args)

  local formatted = adapter.handlers.tools.format_calls(adapter, tools)
  h.eq("run_command", formatted[1]["function"].name)
  h.eq({ cmd = "ls -la" }, vim.json.decode(formatted[1]["function"].arguments))
end

T["Gemini Interactions adapter"]["Streaming"]["can parse tokens from interaction.completed"] = function()
  local tokens
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_streaming.txt")
  for _, line in ipairs(lines) do
    local count = adapter.handlers.response.parse_tokens(adapter, line)
    if count then
      tokens = count
    end
  end

  h.eq(197, tokens)
end

T["Gemini Interactions adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("gemini_interactions", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Gemini Interactions adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_non_streaming.txt")
  data = table.concat(data, "\n")

  local json = { body = data }
  local result = adapter.handlers.response.parse_chat(adapter, json)

  h.expect_starts_with("There are 8 paws", result.output.content)
end

T["Gemini Interactions adapter"]["No Streaming"]["can parse tokens"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_non_streaming.txt")
  data = table.concat(data, "\n")

  local json = { body = data }

  h.eq(240, adapter.handlers.response.parse_tokens(adapter, json))
end

T["Gemini Interactions adapter"]["No Streaming"]["can process a requested tool call"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_tools_turn1.txt")
  data = table.concat(data, "\n")

  local tools = {}
  local json = { body = data }
  adapter.handlers.response.parse_chat(adapter, json, tools)

  h.eq(1, #tools)
  h.eq("call_abc123", tools[1].id)
  h.eq("get_current_temperature", tools[1].name)
  h.eq({ location = "London" }, tools[1].args)
end

T["Gemini Interactions adapter"]["No Streaming"]["can process a completed tool call with text"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_tools_completed.txt")
  data = table.concat(data, "\n")

  local tools = {}
  local json = { body = data }
  local result = adapter.handlers.response.parse_chat(adapter, json, tools)

  h.eq(1, #tools)
  h.eq("get_current_temperature", tools[1].name)
  h.expect_starts_with("The temperature in London", result.output.content)
end

T["Gemini Interactions adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_non_streaming.txt")
  data = table.concat(data, "\n")

  local json = { body = data }

  h.expect_starts_with("There are 8 paws", adapter.handlers.response.parse_inline(adapter, json).output)
end

T["Gemini Interactions adapter"]["No Streaming"]["can output an image description"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_vision.txt")
  data = table.concat(data, "\n")

  local json = { body = data }

  h.expect_starts_with(
    "The local image displays a pipe organ",
    adapter.handlers.response.parse_chat(adapter, json).output.content
  )
end

T["Gemini Interactions adapter"]["No Streaming"]["can output a structured output response"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_interactions_structured_output.txt")
  data = table.concat(data, "\n")

  local json = { body = data }
  local content = adapter.handlers.response.parse_chat(adapter, json).output.content

  local decoded = vim.json.decode(content)
  h.eq("Classic Banana Bread", decoded.recipe_name)
  h.eq(15, decoded.prep_time_minutes)
end

return T
