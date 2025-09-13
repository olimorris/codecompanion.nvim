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

--TODO: Remove this test in v18.0.0
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
            short_name = "test_context",
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
    codecompanion.prompt("test_context")
    local chat = codecompanion.last_chat()
    return chat.context_items
  ]])

  h.eq(2, #refs)
  h.eq("<file>lua/codecompanion/health.lua</file>", refs[1].id)
  h.eq("<file>lua/codecompanion/http.lua</file>", refs[2].id)
end

T["Prompt Library"]["can add context"] = function()
  local items = child.lua([[
    codecompanion.setup({
      prompt_library = {
        ["Test context"] = {
          strategy = "chat",
          description = "Add some references",
          opts = {
            index = 1,
            is_default = true,
            is_slash_cmd = false,
            short_name = "test_context",
            auto_submit = false,
          },
          context = {
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
      },
    })

    codecompanion.prompt("test_context")
    local chat = codecompanion.last_chat()
    return chat.context_items
  ]])

  h.eq(2, #items)
  h.eq("<file>lua/codecompanion/health.lua</file>", items[1].id)
  h.eq("<file>lua/codecompanion/http.lua</file>", items[2].id)
end

T["Prompt Library"]["can add context"] = function()
  local items = child.lua([[
      codecompanion.setup({
        prompt_library = {
          ["Test context"] = {
            strategy = "chat",
            description = "Add some references",
            opts = {
              index = 1,
              is_default = true,
              is_slash_cmd = false,
              short_name = "test_context",
              auto_submit = false,
            },
            context = {
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
        },
      })

      codecompanion.prompt("test_context")
      local chat = codecompanion.last_chat()
      return chat.context_items
    ]])

  h.eq(2, #items)
  h.eq("<file>lua/codecompanion/health.lua</file>", items[1].id)
  h.eq("<file>lua/codecompanion/http.lua</file>", items[2].id)
end

-- New: ensure default_memory adds a memory context item
T["Prompt Library"]["can add memory"] = function()
  local mem_items = child.lua([[
      codecompanion.setup({
        prompt_library = {
          ["Test Prompt"] = {
            strategy = "chat",
            description = "Chat with your test prompt",
            opts = {
              index = 4,
              short_name = "test_prompt",
              ignore_system_prompt = true,
              default_memory = "default",
            },
            prompts = {
              {
                role = "system",
                content = "my prompt",
              },
            },
          },
        },
      })
      codecompanion.prompt("test_prompt")
      local chat = codecompanion.last_chat()
      return chat.context_items
    ]])

  h.eq(1, #mem_items)
  h.eq("<memory>CLAUDE.md</memory>", mem_items[1].id)
end

-- New: ensure ignore_system_prompt prevents adding the configured default system prompt
T["Prompt Library"]["can ignore system prompt"] = function()
  local has_system_tag = child.lua([[
      codecompanion.setup({
        prompt_library = {
          ["No System"] = {
            strategy = "chat",
            description = "No system prompt from config",
            opts = {
              short_name = "no_sys",
              index = 1,
              ignore_system_prompt = true,
            },
            prompts = {
              {
                role = "user",
                content = "Just a user message",
              },
            },
          },
        },
      })
      codecompanion.prompt("no_sys")
      local chat = codecompanion.last_chat()
      for _, msg in ipairs(chat.messages) do
        if msg.opts and msg.opts.tag == "system_prompt_from_config" then
          return true
        end
      end
      return false
    ]])
  h.eq(false, has_system_tag)
end

return T
