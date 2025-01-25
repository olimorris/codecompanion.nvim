local h = require("tests.helpers")
local workspace = require("codecompanion.strategies.chat.slash_commands.workspace")

local new_set = MiniTest.new_set
local T = new_set()

local expect_starts_with = MiniTest.new_expectation(
  -- Expectation subject
  "string starts with",
  -- Predicate
  function(pattern, str)
    return str:find("^" .. pattern) ~= nil
  end,
  -- Fail context
  function(pattern, str)
    return string.format("Expected string to start with: %s\nObserved string: %s", vim.inspect(pattern), str)
  end
)

local chat
local wks
local json

T["Workspace"] = new_set({
  hooks = {
    pre_once = function()
      chat, _ = h.setup_chat_buffer()
      wks = workspace.new({
        Chat = chat,
        context = {},
        opts = {},
      })
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Workspace"]["fetches groups"] = function()
  wks.workspace = wks:read_workspace_file()

  h.eq("Test", wks.workspace.groups[2].name)
end

T["Workspace"]["adds files and symbols"] = function()
  h.eq(1, #chat.messages)
  wks:output("Test")

  h.eq(6, #chat.messages)
  h.eq(
    'Test description for the file stub.go located at tests/stubs/stub.go\n\n```go\nimport (\n\t"math"\n)\n\ntype ExampleStruct struct {\n\tValue float64\n}\n\nfunc (e ExampleStruct) Compute() float64 {\n\treturn math.Sqrt(e.Value)\n}\n\n\n```',
    chat.messages[3].content
  )
  expect_starts_with(
    "Test symbol description for the file stub.lua located at tests/stubs/stub.lua",
    chat.messages[5].content
  )
  expect_starts_with("Here is a symbolic outline of the file `tests/stubs/stub.py`", chat.messages[6].content)
end

return T
