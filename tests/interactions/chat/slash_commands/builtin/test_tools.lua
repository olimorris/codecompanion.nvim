local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        chat = h.setup_chat_buffer()

        function run_tools_picker(choice)
          local listed = {}
          vim.ui.select = function(items, _, on_choice)
            listed = vim.tbl_map(function(item)
              return item.name
            end, items)
            on_choice(vim.iter(items):find(function(item)
              return item.name == choice
            end))
          end

          local SlashCommand = require("codecompanion.interactions.chat.slash_commands.builtin.tools")
          SlashCommand.new({ Chat = chat, config = { opts = { provider = "default" } }, context = {} })
            :execute(require("codecompanion.interactions.chat.slash_commands").new())
          return listed
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Tools"] = MiniTest.new_set()

T["Tools"]["adds the selected tool to the chat"] = function()
  h.is_true(child.lua([[
    run_tools_picker("weather")
    return chat.tool_registry.in_use.weather
  ]]))
end

T["Tools"]["adds the tools in a selected group"] = function()
  local in_use = child.lua([[
    run_tools_picker("test_group")
    return chat.tool_registry.in_use
  ]])

  h.eq(true, in_use.func)
  h.eq(true, in_use.weather)
end

T["Tools"]["DOES NOT list a tool that is ALREADY in the chat"] = function()
  local listed = child.lua([[
    chat.tool_registry:add("weather")
    return run_tools_picker(nil)
  ]])

  h.is_true(vim.tbl_contains(listed, "func"))
  h.is_false(vim.tbl_contains(listed, "weather"))
end

return T
