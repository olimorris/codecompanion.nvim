local h = require("tests.helpers")
local transform = require("codecompanion.utils.tool_transformers")

local new_set = MiniTest.new_set
T = new_set()

T["Transformers"] = new_set({})

T["Transformers"]["can transform to Anthropic schema"] = function()
  local openai = vim.fn.readfile("tests/adapters/http/stubs/transformers/openai.txt")
  openai = vim.json.decode(table.concat(openai, "\n"))

  local anthropic = vim.fn.readfile("tests/adapters/http/stubs/transformers/anthropic.txt")
  anthropic = vim.json.decode(table.concat(anthropic, "\n"))

  local output = transform.to_anthropic(openai)

  h.eq(output, anthropic)
end

return T
