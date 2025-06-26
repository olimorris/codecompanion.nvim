local config = require("tests.config")
local h = require("tests.helpers")

local workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace.json"), ""))

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

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

T["Workspace"]["can remove the default system prompt"] = function()
  child.lua([[
  _G.set_workspace()
  _G.wks:output("Test 2")
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  h.eq(workspace_json.system_prompt, messages[1].content)
  h.eq(workspace_json.groups[2].system_prompt, messages[2].content)
end

T["Workspace"]["files and symbols are added to the chat"] = function()
  child.lua([[
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

T["Workspace"]["can open a file as a buffer if it's already open"] = function()
  child.lua([[
    -- Comment this out and see that it's loaded as a file instead
    vim.cmd("edit tests/stubs/stub.go")

    _G.set_workspace()
    _G.wks:output("Test")
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  h.expect_starts_with([[Test description for the file stub.go located at tests/stubs/stub.go]], messages[5].content)
end

T["Workspace"]["top-level prompts are not duplicated and are ordered correctly"] = function()
  workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace_multiple.json"), ""))

  child.lua([[
  _G.set_workspace("tests/stubs/workspace_multiple.json")
  ]])

  child.lua([[
  _G.wks:output("Test 1")
  _G.wks:output("Test 2")
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  h.eq(workspace_json.system_prompt, messages[1].content)
  h.eq(workspace_json.groups[1].system_prompt, messages[2].content)
  h.eq(workspace_json.groups[2].system_prompt, messages[3].content)
  h.expect_starts_with(workspace_json.data["test1-file"].description, messages[4].content)
end

T["Workspace"]["variables can be fetched from top level and at a group level"] = function()
  workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace_vars.json"), ""))

  child.lua([[
  _G.set_workspace("tests/stubs/workspace_vars.json")
  ]])

  child.lua([[
  _G.wks:output("Test")
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  h.eq(workspace_json.vars.var_description, messages[4].content)
  h.expect_starts_with(workspace_json.vars.var_hello, messages[5].content)
end

T["Workspace"]["variables at the group level take priority"] = function()
  workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace_vars.json"), ""))

  child.lua([[
  _G.set_workspace("tests/stubs/workspace_vars.json")
  ]])

  child.lua([[
  _G.wks:output("Test 2")
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  h.eq(workspace_json.groups[2].vars.var_hello, messages[4].content)
end

T["Workspace"]["variables are replaced in paths"] = function()
  workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace_vars.json"), ""))

  child.lua([[
  _G.set_workspace("tests/stubs/workspace_vars.json")
  ]])

  child.lua([[
  _G.wks:output("Test 3")
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  -- stub-txt is resolved
  h.expect_contains("Some text", messages[5].content)
end

-- T["Workspace"]["same data isn't inserted twice"] = function()
--   workspace_json = vim.json.decode(table.concat(vim.fn.readfile("tests/stubs/workspace_vars.json"), ""))
--
--   child.lua([[
--   _G.set_workspace("tests/stubs/workspace.json")
--   ]])
--
--   child.lua([[
--   _G.wks:output("Test")
--   _G.wks:output("Test 4")
--   ]])
--
--   local messages = child.lua_get([[_G.chat.messages]])
--
--   h.eq("This is a test group", messages[5].content)
--   h.expect_contains("stub.lua", messages[7].content)
--
--   h.eq("Test for adding the same file twice", messages[8].content)
--   h.eq("stubs.lua", messages[9].content)
-- end

return T
