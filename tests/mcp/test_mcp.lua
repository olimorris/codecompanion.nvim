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
            opts = {
              default_servers = { "sequential-thinking", "tavily-mcp" },
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
    local result = MCP.transform_to_acp()
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
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

T["MCP"]["get_prompts() gathers prompts from every ready server"] = function()
  local result = child.lua([[
    local Client = require("codecompanion.mcp.client")
    local MockMCPClientTransport = require("tests.mocks.mcp_client_transport")
    local prompts_by_server = {
      ["sequential-thinking"] = { { name = "think" } },
      ["tavily-mcp"] = { { name = "search" }, { name = "extract" } },
    }

    Client.static.methods.new_transport.default = function(args)
      local transport = MockMCPClientTransport:new()
      transport:expect_jsonrpc_call("initialize", function(params)
        return "result", {
          protocolVersion = params.protocolVersion,
          capabilities = { prompts = {} },
          serverInfo = { name = args.name, version = "1.0.0" },
        }
      end)
      transport:expect_jsonrpc_notify("notifications/initialized", function() end)
      transport:expect_jsonrpc_call("prompts/list", function()
        return "result", { prompts = prompts_by_server[args.name] }
      end)
      return transport
    end

    local ready = 0
    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionMCPServerReady",
      callback = function() ready = ready + 1 end,
    })
    MCP.start_servers()
    vim.wait(1000, function() return ready == 2 end)

    local prompts
    MCP.get_prompts({ callback = function(result) prompts = result end })
    vim.wait(1000, function() return prompts ~= nil end)
    return vim.tbl_map(function(item) return { item.server, item.prompt.name } end, prompts)
  ]])

  h.eq({
    { "sequential-thinking", "think" },
    { "tavily-mcp", "extract" },
    { "tavily-mcp", "search" },
  }, result)
end

T["MCP"]["transform_to_acp()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

T["MCP"]["transform_to_acp()"]["includes only default_servers"] = function()
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
          },
        },
        opts = {
          default_servers = { "included-server" },
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

T["MCP"]["transform_to_acp()"]["excludes all servers when default_servers is empty"] = function()
  child.lua([[
    MCP = require("codecompanion.mcp")
    h = require("tests.helpers")
    h.setup_plugin({
      mcp = {
        servers = {
          ["server-a"] = { cmd = { "npx", "-y", "server-a" } },
          ["server-b"] = { cmd = { "npx", "-y", "server-b" } },
        },
        opts = {
          default_servers = {},
        },
      },
    })
  ]])

  local result = child.lua([[
    return MCP.transform_to_acp()
  ]])

  h.eq({}, result)
end

return T
