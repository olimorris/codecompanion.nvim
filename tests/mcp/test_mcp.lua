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

T["MCP"]["transform_to_acp()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

T["MCP"]["transform_to_acp()"]["excludes server with add_to_chat = false"] = function()
  child.lua([[
    MCP = require("codecompanion.mcp")
    h = require("tests.helpers")
    h.setup_plugin({
      mcp = {
        servers = {
          ["included-server"] = {
            cmd = { "npx", "-y", "included-server" },
          },
          ["excluded-server"] = {
            cmd = { "npx", "-y", "excluded-server" },
            opts = { add_to_chat = false },
          },
        },
      },
    })
  ]])

  local result = child.lua([[
    return MCP.transform_to_acp()
  ]])

  h.eq(1, #result)
  h.eq("included-server", result[1].name)
end

T["MCP"]["transform_to_acp()"]["excludes all servers when global add_to_chat = false"] = function()
  child.lua([[
    MCP = require("codecompanion.mcp")
    h = require("tests.helpers")
    h.setup_plugin({
      mcp = {
        add_to_chat = false,
        servers = {
          ["server-a"] = { cmd = { "npx", "-y", "server-a" } },
          ["server-b"] = { cmd = { "npx", "-y", "server-b" } },
        },
      },
    })
  ]])

  local result = child.lua([[
    return MCP.transform_to_acp()
  ]])

  h.eq({}, result)
end

T["MCP"]["transform_to_acp()"]["server add_to_chat = true overrides global add_to_chat = false"] = function()
  child.lua([[
    MCP = require("codecompanion.mcp")
    h = require("tests.helpers")
    h.setup_plugin({
      mcp = {
        add_to_chat = false,
        servers = {
          ["opt-in-server"] = {
            cmd = { "npx", "-y", "opt-in-server" },
            opts = { add_to_chat = true },
          },
          ["excluded-server"] = { cmd = { "npx", "-y", "excluded-server" } },
        },
      },
    })
  ]])

  local result = child.lua([[
    return MCP.transform_to_acp()
  ]])

  h.eq(1, #result)
  h.eq("opt-in-server", result[1].name)
end

return T
