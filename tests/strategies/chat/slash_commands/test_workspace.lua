local config = require("tests.config")
local h = require("tests.helpers")

local workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace.json"), ""))

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      child.lua([[
        h = require('tests.helpers')
        _G.chat, _ = h.setup_chat_buffer()

        _G.wks = require("codecompanion.strategies.chat.slash_commands.workspace").new({
          Chat = chat,
          context = {},
          opts = {},
        })

        function _G.set_workspace(path)
          path = path or "tests/stubs/workspace.json"
          _G.wks.workspace = _G.wks:read_workspace_file(path)
        end
]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Workspace"] = new_set()

T["Workspace"]["fetches groups"] = function()
  child.lua([[_G.set_workspace()]])
  local wks_group = child.lua_get([[_G.wks.workspace.groups]])

  h.eq("Test", wks_group[1].name)
  h.eq("Test 2", wks_group[2].name)
end

T["Workspace"]["system prompts are added in the correct order along with a group description"] = function()
  child.lua([[
  --require("tests.log")
  _G.set_workspace()
  ]])

  local messages = child.lua_get([[_G.chat.messages]])
  h.eq(1, #messages)

  child.lua([[_G.wks:output("Test")]])

  messages = child.lua_get([[_G.chat.messages]])

  h.eq(config.opts.system_prompt, messages[1].content)
  h.eq(workspace_json.system_prompt, messages[2].content)
  h.eq(workspace_json.groups[1].system_prompt, messages[3].content)

  h.eq(workspace_json.groups[1].description, messages[4].content)
end

T["Workspace"]["files and symbols are added to the chat"] = function()
  child.lua([[
  --require("tests.log")
  _G.set_workspace()
  ]])

  local messages = child.lua_get([[_G.chat.messages]])
  h.eq(1, #messages)

  child.lua([[_G.wks:output("Test")]])

  messages = child.lua_get([[_G.chat.messages]])

  h.eq(
    'Test description for the file stub.go located at tests/stubs/stub.go\n\n```go\nimport (\n\t"math"\n)\n\ntype ExampleStruct struct {\n\tValue float64\n}\n\nfunc (e ExampleStruct) Compute() float64 {\n\treturn math.Sqrt(e.Value)\n}\n\n\n```',
    messages[5].content
  )
  h.expect_starts_with(
    "Test symbol description for the file stub.lua located at tests/stubs/stub.lua",
    messages[6].content
  )
end

-- T["Workspace"]["can remove the default system prompt"] = function()
--   set_workspace()
--   wks:output("Test 2")
--
--   h.eq("system", chat.messages[1].role)
--   h.eq("Testing to remove the default system prompt", chat.messages[1].content)
--   h.eq("user", chat.messages[2].role)
-- end
--
-- T["Workspace"]["can add system prompts"] = function()
--   set_workspace("tests/stubs/workspace_system_prompt.json")
--   wks:output("Test")
--
--   h.eq("system", chat.messages[1].role)
--   h.eq("High level system prompt", chat.messages[1].content)
-- end
--
-- T["Workspace"]["top-level prompts are not duplicated and are ordered correctly"] = function()
--   set_workspace("tests/stubs/workspace_multiple.json")
--   wks:output("Test 1")
--   wks:output("Test 2")
--
--   h.eq("High level system prompt", chat.messages[1].content)
--   h.eq("Group prompt 1", chat.messages[2].content)
--   h.eq("Group prompt 2", chat.messages[3].content)
--   h.expect_starts_with("A test description", chat.messages[4].content)
-- end

return T
