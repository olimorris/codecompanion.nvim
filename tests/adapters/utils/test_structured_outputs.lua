local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        transform = require("codecompanion.adapters.utils.structured_outputs")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Structured Outputs"] = new_set()

T["Structured Outputs"]["can transform to Anthropic"] = function()
  local output = child.lua([[
    local input = vim.fn.readfile("tests/adapters/utils/stubs/input.json")
    input = vim.json.decode(table.concat(input, "\n"))

    local anthropic = vim.fn.readfile("tests/adapters/utils/stubs/anthropic_structured_output.json")
    anthropic = vim.json.decode(table.concat(anthropic, "\n"))

    local output = transform.to_anthropic(input)

    return { anthropic, output }
  ]])

  h.eq(output[1], output[2])
end

T["Structured Outputs"]["can transform to Gemini"] = function()
  local output = child.lua([[
    local input = vim.fn.readfile("tests/adapters/utils/stubs/input.json")
    input = vim.json.decode(table.concat(input, "\n"))

    local gemini = vim.fn.readfile("tests/adapters/utils/stubs/gemini_structured_output.json")
    gemini = vim.json.decode(table.concat(gemini, "\n"))

    local output = transform.to_gemini(input)

    return { gemini, output }
  ]])

  h.eq(output[1], output[2])
end

T["Structured Outputs"]["can transform to Ollama"] = function()
  local output = child.lua([[
    local input = vim.fn.readfile("tests/adapters/utils/stubs/input.json")
    input = vim.json.decode(table.concat(input, "\n"))

    local ollama = vim.fn.readfile("tests/adapters/utils/stubs/ollama_structured_output.json")
    ollama = vim.json.decode(table.concat(ollama, "\n"))

    local output = transform.to_ollama(input)

    return { ollama, output }
  ]])

  h.eq(output[1], output[2])
end

T["Structured Outputs"]["can transform to OpenAI"] = function()
  local output = child.lua([[
    local input = vim.fn.readfile("tests/adapters/utils/stubs/input.json")
    input = vim.json.decode(table.concat(input, "\n"))

    local openai = vim.fn.readfile("tests/adapters/utils/stubs/openai_structured_output.json")
    openai = vim.json.decode(table.concat(openai, "\n"))

    local output = transform.to_openai(input)

    return { openai, output }
  ]])

  h.eq(output[1], output[2])
end

T["Structured Outputs"]["can transform to OpenAI Responses"] = function()
  local output = child.lua([[
    local input = vim.fn.readfile("tests/adapters/utils/stubs/input.json")
    input = vim.json.decode(table.concat(input, "\n"))

    local openai_responses = vim.fn.readfile("tests/adapters/utils/stubs/openai_responses_structured_output.json")
    openai_responses = vim.json.decode(table.concat(openai_responses, "\n"))

    local output = transform.to_openai_responses(input)

    return { openai_responses, output }
  ]])

  h.eq(output[1], output[2])
end

return T
