local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        codecompanion = require("codecompanion")
        MCP = require("codecompanion.mcp")
        h = require('tests.helpers')
        h.setup_plugin({
          mcp = {
            servers = {
              ["sequential-thinking"] = {
                cmd = { "npx", "-y", "@modelcontextprotocol/server-sequential-thinking" },
                opts = {
                  add_to_chat = true,
                  auto_start = true,
                },
              },
              ["tavily-mcp"] = {
                cmd = { "npx", "-y", "tavily-mcp@latest" },
                env = {
                  TAVILY_API_KEY = "ABC-123",
                },
                tool_defaults = {
                  require_approval_before = true,
                },
              },
            },
          },
        })
      ]])
    end,
    post_once = child.stop,
  },
})

T["MCP"] = MiniTest.new_set()

T["MCP"]["start() starts and initializes the client once"] = function()
  local transformed_config = child.lua([[
    return MCP.transform_to_acp()
  ]])

  h.eq({
    {
      name = "sequential-thinking",
      command = "npx",
      args = { "-y", "@modelcontextprotocol/server-sequential-thinking" },
      env = {},
    },
    {
      name = "tavily-mcp",
      command = "npx",
      args = { "-y", "tavily-mcp@latest" },
      env = {
        TAVILY_API_KEY = "ABC-123",
      },
    },
  }, transformed_config)
end

return T
