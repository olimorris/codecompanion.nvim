local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        chat = h.setup_chat_buffer()

        function register_external_server()
          require("codecompanion.mcp").register_tools("external", {
            mcp__external__search = {
              description = "Search",
              visible = false,
              callback = function()
                return {
                  name = "mcp__external__search",
                  schema = {
                    type = "function",
                    ["function"] = { name = "mcp__external__search", parameters = { type = "object", properties = {} } },
                  },
                  cmds = { function() return { status = "success" } end },
                }
              end,
            },
          }, {
            description = "Tools from MCP Server `external`",
            tools = { "mcp__external__search" },
            opts = { collapse_tools = true },
          })
        end

        SlashCommand = require("codecompanion.interactions.chat.slash_commands.builtin.mcp")

        function open_picker(choose)
          local picker_items
          vim.ui.select = function(items, _, on_choice)
            picker_items = items
            on_choice(choose and choose(items))
          end
          SlashCommand.new({ Chat = chat, config = { opts = { provider = "default" } }, context = {} })
            :execute(require("codecompanion.interactions.chat.slash_commands"))
          return vim.tbl_map(function(item)
            return { name = item.name, type = item.type }
          end, picker_items)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["MCP"] = MiniTest.new_set()

T["MCP"]["is disabled without configured servers or registered groups"] = function()
  local result = child.lua([[
    require("codecompanion.config").mcp.servers = {}
    local enabled_before_registration = SlashCommand.enabled()
    register_external_server()
    local enabled_after_registration = SlashCommand.enabled()
    return {
      enabled_before_registration = enabled_before_registration,
      enabled_after_registration = enabled_after_registration,
    }
  ]])

  h.is_false(result.enabled_before_registration)
  h.is_true(result.enabled_after_registration)
end

T["MCP"]["adds a registered group's tools to the chat from the picker"] = function()
  local result = child.lua([[
    require("codecompanion.config").mcp.servers = {}
    register_external_server()
    local picker_items = open_picker(function(items)
      return vim.iter(items):find(function(item) return item.type == "registered" end)
    end)
    return { picker_items = picker_items, in_use = chat.tool_registry.in_use }
  ]])

  h.eq({ { name = "external", type = "registered" } }, result.picker_items)
  h.is_true(result.in_use["mcp__external__search"])
end

T["MCP"]["DOES NOT list a configured server's group twice"] = function()
  local picker_items = child.lua([[
    require("codecompanion.config").mcp.servers = { external = { cmd = { "external-server" } } }
    register_external_server()
    return open_picker()
  ]])

  h.eq({ { name = "external", type = "configured" } }, picker_items)
end

return T
