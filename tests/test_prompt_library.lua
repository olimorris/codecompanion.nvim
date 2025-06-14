local h = require("tests.helpers")
local new_set = MiniTest.new_set
local T = new_set()
local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        codecompanion = require("codecompanion")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Prompt Library"] = new_set()

T["Prompt Library"]["can specify separate adapter and model"] = function()
  local adapter = child.lua([[
    codecompanion.setup({
      prompt_library = {
        ["Test Adapter"] = {
          strategy = "chat",
          description = "Testing that different adapters work",
          opts = {
            index = 1,
            short_name = "test_adapters",
            adapter = {
              name = "copilot",
              model = "gpt-4.1",
            },
          },
          prompts = {
            {
              role = "foo",
              content = "I can use different adapters",
            },
          },
        },
      }
    })
    --require("tests.log")
    codecompanion.prompt("test_adapters")
    return {
      name = codecompanion.last_chat().adapter.name,
      model = codecompanion.last_chat().adapter.schema.model.default
    }
  ]])

  h.eq("copilot", adapter.name)
  h.eq("gpt-4.1", adapter.model)
end

T["Prompt Library"]["can add references"] = function()
  local refs = child.lua([[
    codecompanion.setup({
      prompt_library = {
        ["Test References"] = {
          strategy = "chat",
          description = "Add some references",
          opts = {
            index = 1,
            is_default = true,
            is_slash_cmd = false,
            short_name = "test_ref",
            auto_submit = false,
          },
          references = {
            {
              type = "file",
              path = {
                "lua/codecompanion/health.lua",
                "lua/codecompanion/http.lua",
              },
            },
          },
          prompts = {
            {
              role = "foo",
              content = "I need some references",
            },
          },
        },
      }
    })
    codecompanion.prompt("test_ref")
    local chat = codecompanion.last_chat()
    return chat.refs
  ]])

  h.eq(2, #refs)
  h.eq("<file>lua/codecompanion/health.lua</file>", refs[1].id)
  h.eq("<file>lua/codecompanion/http.lua</file>", refs[2].id)
end

return T
