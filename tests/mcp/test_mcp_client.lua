local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        Client = require("codecompanion.mcp.client")
        MockMCPClientTransport = require("tests.mocks.mcp_client_transport")
        TRANSPORT = MockMCPClientTransport:new()
        function mock_new_transport()
          return TRANSPORT
        end

        function read_mcp_tools()
          return vim
            .iter(vim.fn.readfile("tests/stubs/mcp/tools.jsonl"))
            :map(function(s)
              return s ~= "" and vim.json.decode(s) or nil
            end)
            :totable()
        end

        function setup_default_initialization()
          TRANSPORT:expect_jsonrpc_call("initialize", function(params)
            return "result", {
              protocolVersion = params.protocolVersion,
              capabilities = { tools = {} },
              serverInfo = { name = "Test MCP Server", version = "1.0.0" },
            }
          end)
          TRANSPORT:expect_jsonrpc_notify("notifications/initialized", function() end)
        end

        function setup_tool_list(tools)
          TRANSPORT:expect_jsonrpc_call("tools/list", function()
            return "result", { tools = tools or read_mcp_tools() }
          end)
        end

        function start_client_and_wait_loaded()
          local tools_loaded
          -- NOTE: We rely on this event to know when tools are loaded
          vim.api.nvim_create_autocmd("User", {
            pattern = "CodeCompanionMCPServerToolsLoaded",
            once = true,
            callback = function() tools_loaded = true end,
          })

          CLI = Client.new({ name = "testMcp", cfg = { cmd = { "test-mcp" } }, methods = { new_transport = mock_new_transport } })
          CLI:start()
          vim.wait(1000, function() return tools_loaded end)
        end
      ]])
    end,
    post_case = function()
      h.is_true(child.lua_get("TRANSPORT:all_handlers_consumed()"))
    end,
    post_once = child.stop,
  },
})

T["MCP Client"] = MiniTest.new_set()
T["MCP Client"]["start() starts and initializes the client once"] = function()
  child.lua([[
    READY = false
    INIT_PARAMS = {}

    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionMCPServerReady",
      once = true,
      callback = function() READY = true end,
    })

    TRANSPORT:expect_jsonrpc_call("initialize", function(params)
      table.insert(INIT_PARAMS, params)
      return "result", {
        protocolVersion = params.protocolVersion,
        capabilities = { tools = {} },
        serverInfo = { name = "Test MCP Server", version = "1.0.0" },
      }
    end)
    TRANSPORT:expect_jsonrpc_notify("notifications/initialized", function() end)

    setup_tool_list()
    CLI = Client.new({ name = "testMcp", cfg = { cmd = { "test-mcp" } }, methods = { new_transport = mock_new_transport } })
    CLI:start()
    CLI:start()  -- repeated call should be no-op
    CLI:start()
    vim.wait(1000, function() return READY end)
    CLI:start()  -- repeated call should be no-op
    CLI:start()
  ]])

  h.is_true(child.lua_get("READY"))
  h.eq(child.lua_get("INIT_PARAMS[1]"), {
    protocolVersion = "2025-11-25",
    clientInfo = {
      name = "CodeCompanion.nvim",
      version = "NO VERSION",
    },
    capabilities = {},
  })
  h.is_true(child.lua_get("CLI.ready"))
end

T["MCP Client"]["tools are loaded in pages"] = function()
  local result = child.lua([[
    setup_default_initialization()

    local mcp_tools = read_mcp_tools()
    local page_size = 2
    TRANSPORT:expect_jsonrpc_call("tools/list", function(params)
      local start_idx = tonumber(params.cursor) or 1
      local end_idx = math.min(start_idx + page_size - 1, #mcp_tools)
      local page_tools = {}
      for i = start_idx, end_idx do
        table.insert(page_tools, mcp_tools[i])
      end
      local next_cursor = end_idx < #mcp_tools and tostring(end_idx + 1) or nil
      return "result", { tools = page_tools, nextCursor = next_cursor }
    end, { repeats = math.ceil(#mcp_tools / page_size) })

    start_client_and_wait_loaded()

    -- Get tools from the MCP registry (not config)
    local mcp = require("codecompanion.mcp")
    local registered_tools, registered_groups = mcp.get_registered_tools()
    local group = registered_groups["mcp:testMcp"]
    local tools = vim
      .iter(registered_tools)
      :filter(function(_, v)
        return vim.tbl_get(v, "opts", "_mcp_info", "server") == "testMcp"
      end)
      :fold({}, function(acc, k, v)
        v = vim.deepcopy(v)
        -- functions cannot cross process boundary
        v.callback.cmds = nil
        v.callback.output = nil
        acc[k] = v
        return acc
      end)
    return {
      mcp_tools = read_mcp_tools(),
      group = group,
      tools = tools,
    }
  ]])

  local mcp_tools = result.mcp_tools
  local tools = result.tools
  local group = result.group

  h.eq(vim.tbl_count(tools), #mcp_tools)
  h.eq(#group.tools, #mcp_tools)
  for _, mcp_tool in ipairs(mcp_tools) do
    local cc_tool_name = "testMcp_" .. mcp_tool.name
    h.expect_tbl_contains(cc_tool_name, group.tools)

    local cc_tool = tools[cc_tool_name]
    h.expect_truthy(cc_tool)
    h.eq(mcp_tool.title or mcp_tool.name, cc_tool.description)
    h.is_false(cc_tool.visible)
    h.eq({
      type = "function",
      ["function"] = {
        name = cc_tool_name,
        description = mcp_tool.description,
        parameters = mcp_tool.inputSchema,
        strict = true,
      },
    }, cc_tool.callback.schema)
  end

  h.expect_contains("testMcp", group.prompt)
end

T["MCP Client"]["can process tool calls"] = function()
  local result = child.lua([[
    setup_default_initialization()
    setup_tool_list()
    start_client_and_wait_loaded()

    TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      if params.name == "echo" then
        local value = params.arguments.value
        if value == nil then
          return "result", { isError = true, content = { { type = "text", text = "No value" } } }
        end
        return "result", { content = { { type = "text", text = params.arguments.value } } }
      else
        return "error", { code = -32601, message = "Tool not found" }
      end
    end, { repeats = 3 })

    local call_results = {}
    local function append_call_result(ok, result_or_error)
      table.insert(call_results, { ok, result_or_error })
    end
    CLI:call_tool("echo", { value = "xxxyyyzzz" }, append_call_result)
    CLI:call_tool("echo", {}, append_call_result)
    CLI:call_tool("nonexistent_tool", {}, append_call_result)
    vim.wait(1000, function() return #call_results == 3 end)
    return call_results
  ]])

  h.eq({
    { true, { content = { { type = "text", text = "xxxyyyzzz" } } } },
    { true, { isError = true, content = { { type = "text", text = "No value" } } } },
    { false, "MCP JSONRPC error: [-32601] Tool not found" },
  }, result)
end

T["MCP Client"]["can handle reordered tool call responses"] = function()
  local result = child.lua([[
    setup_default_initialization()
    setup_tool_list()
    start_client_and_wait_loaded()

    local latencies = { 300, 50, 150, 400 }
    for _, latency in ipairs(latencies) do
      TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
        return "result", { content = { { type = "text", text = params.arguments.value } } }
      end, { latency_ms = latency })
    end

    local call_results = {}
    local function append_call_result(ok, result_or_error)
      table.insert(call_results, { ok, result_or_error })
    end
    for i, latency in ipairs(latencies) do
      CLI:call_tool("echo", { value = string.format("%d_%d", i, latency) }, append_call_result)
    end
    vim.wait(1000, function() return #call_results == #latencies end)
    return call_results
  ]])

  h.eq({
    { true, { content = { { type = "text", text = "2_50" } } } },
    { true, { content = { { type = "text", text = "3_150" } } } },
    { true, { content = { { type = "text", text = "1_300" } } } },
    { true, { content = { { type = "text", text = "4_400" } } } },
  }, result)
end

T["MCP Client"]["respects timeout option for tool calls"] = function()
  local result = child.lua([[
    setup_default_initialization()
    setup_tool_list()
    start_client_and_wait_loaded()

    TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      return "result", { content = { { type = "text", text = "fast response" } } }
    end)
    TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      return "result", { content = { { type = "text", text = "slow response" } } }
    end, { latency_ms = 200 })
    TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      return "result", { content = { { type = "text", text = "very slow response" } } }
    end, { latency_ms = 200 })

    local call_results = {}
    local function append_call_result(ok, result_or_error)
      table.insert(call_results, { ok, result_or_error })
    end

    CLI:call_tool("echo", { value = "no_timeout" }, append_call_result)
    CLI:call_tool("echo", { value = "short_timeout" }, append_call_result, { timeout = 100 })
    CLI:call_tool("echo", { value = "long_timeout" }, append_call_result, { timeout = 1000 })

    vim.wait(2000, function() return #call_results == 3 end)
    return call_results
  ]])

  h.is_true(result[1][1])
  h.eq(result[1][2].content[1].text, "fast response")

  h.is_false(result[2][1])
  h.expect_contains("timed out", result[2][2])

  h.is_true(result[3][1])
  h.eq(result[3][2].content[1].text, "very slow response")
end

T["MCP Client"]["roots capability is declared when roots config is provided"] = function()
  local result = child.lua([[
    setup_default_initialization()
    setup_tool_list()

    local roots = {
      { uri = "file:///home/user/project1", name = "Project 1" },
      { uri = "file:///home/user/project2", name = "Project 2" },
    }

    CLI = Client.new({
      name = "testMcp",
      cfg = {
        cmd = { "test-mcp" },
        roots = function() return roots end,
      },
      methods = { new_transport = mock_new_transport },
    })
    CLI:start()
    vim.wait(1000, function() return CLI.ready end)

    local received_resp
    TRANSPORT:send_request_to_client("roots/list", nil, function(status, result)
      received_resp = { status, result }
    end)

    vim.wait(1000, function() return received_resp ~= nil end)
    return { roots = roots, received_resp = received_resp }
  ]])

  h.eq(result.received_resp[1], "result")
  h.eq(result.received_resp[2], { roots = result.roots })
end

T["MCP Client"]["roots list changed notification is sent when roots change"] = function()
  local result = child.lua([[
    setup_default_initialization()
    setup_tool_list()

    local root_lists = {
      {},
      {
        { uri = "file:///home/user/projectA", name = "Project A" },
      },
      {
        { uri = "file:///home/user/projectA", name = "Project A" },
        { uri = "file:///home/user/projectB", name = "Project B" },
      },
      {
        { uri = "file:///home/user/projectC", name = "Project C" },
      },
    }
    local current_roots

    local notify_roots_list_changed
    CLI = Client.new({
      name = "testMcp",
      cfg = {
        cmd = { "test-mcp" },
        roots = function() return current_roots end,
        register_roots_list_changed = function(notify)
          notify_roots_list_changed = notify
        end,
      },
      methods = { new_transport = mock_new_transport },
    })
    CLI:start()
    vim.wait(1000, function() return CLI.ready end)

    local received_resps = {}
    for i = 1, #root_lists do
      if current_roots ~= nil then
        TRANSPORT:expect_jsonrpc_notify("roots/listChanged", function() end)
        notify_roots_list_changed()
        vim.wait(1000, function() return TRANSPORT:all_handlers_consumed() end)
      end
      current_roots = root_lists[i]
      TRANSPORT:send_request_to_client("roots/list", nil, function(status, result)
        received_resps[i] = { status, result }
      end)
      vim.wait(1000, function() return received_resps[i] ~= nil end)
    end

    return { received_resps = received_resps, root_lists = root_lists }
  ]])

  for i, roots in ipairs(result.root_lists) do
    h.eq(result.received_resps[i][1], "result")
    h.eq(result.received_resps[i][2], { roots = roots })
  end
end

T["MCP Client"]["transport closed automatically on initialization failure"] = function()
  child.lua([[
    TRANSPORT:expect_jsonrpc_call("initialize", function(params)
      return "error", { code = -32603, message = "Initialization failed" }
    end)

    CLI = Client.new({ name = "testMcp", cfg = { cmd = { "test-mcp" } }, methods = { new_transport = mock_new_transport } })
    CLI:start()
    vim.wait(1000, function() return TRANSPORT:all_handlers_consumed() end)
    vim.wait(1000, function() return not CLI.ready end)
  ]])

  h.is_false(child.lua_get("CLI.ready"))
  h.is_false(child.lua_get("TRANSPORT:started()"))
end

T["MCP Client"]["stop() cleans up pending requests"] = function()
  local call_result = child.lua([[
    setup_default_initialization()
    setup_tool_list()
    start_client_and_wait_loaded()

    -- initiate a SLOW tool call that won't respond before stop()
    TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      return "result", { content = { { type = "text", text = "slow response" } } }
    end, { latency_ms = 1000 })

    local call_result
    CLI:call_tool("echo", { value = "will be cancelled" }, function(ok, result_or_error)
      call_result = { ok, result_or_error }
    end)

    vim.wait(50, function() return call_result ~= nil end)
    CLI:stop()
    vim.wait(1000, function() return call_result ~= nil end)
    return call_result
  ]])

  h.is_false(child.lua_get("CLI.ready"))
  h.is_false(child.lua_get("TRANSPORT:started()"))
  h.is_false(call_result[1])
  h.expect_contains("close", call_result[2])
end

return T
