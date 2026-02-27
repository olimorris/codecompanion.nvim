local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        local h = require("tests.helpers")
        Client = require("codecompanion.mcp.client")
        MockMCPClientTransport = require("tests.mocks.mcp_client_transport")

        MCP_TOOLS = vim
          .iter(vim.fn.readfile("tests/stubs/mcp/tools.jsonl"))
          :map(function(s)
            if s ~= "" then
              return vim.json.decode(s)
            end
          end)
          :totable()

        MATH_MCP_TRANSPORT = MockMCPClientTransport:new()
        MATH_MCP_TOOLS = vim.iter(MCP_TOOLS):filter(function(tool)
          return vim.startswith(tool.name, "math_")
        end):totable()

        OTHER_MCP_TRANSPORT = MockMCPClientTransport:new()
        OTHER_MCP_TOOLS = vim.iter(MCP_TOOLS):filter(function(tool)
          return not vim.startswith(tool.name, "math_")
        end):totable()

        ---Setup expectations for MCP server initialization handshake
        ---@param transport CodeCompanion.MCP.MockMCPClientTransport
        ---@param tools MCP.Tool[]
        ---@param server_instructions? string
        local function setup_mcp_init_expectations(transport, tools, server_instructions)
          transport:expect_jsonrpc_call("initialize", function(params)
            return "result", {
              protocolVersion = params.protocolVersion,
              capabilities = { tools = {} },
              serverInfo = { name = "Test MCP Server", version = "1.0.0" },
              instructions = server_instructions or "Test MCP server instructions.",
            }
          end)
          transport:expect_jsonrpc_notify("notifications/initialized", function(params) end)
          transport:expect_jsonrpc_call("tools/list", function()
            return "result", { tools = tools }
          end)
        end

        ---Get the transport and tools for a given server command
        ---@param cmd string The first element of the server cmd array
        ---@return CodeCompanion.MCP.MockMCPClientTransport, MCP.Tool[]
        local function get_transport_and_tools(cmd)
          if cmd == "math_mcp" then
            return MATH_MCP_TRANSPORT, MATH_MCP_TOOLS
          else
            return OTHER_MCP_TRANSPORT, OTHER_MCP_TOOLS
          end
        end

        ---Create a transport factory that injects mock transports
        ---@param server_instructions? string Optional custom server instructions
        ---@return fun(args: CodeCompanion.MCP.StdioTransportArgs): CodeCompanion.MCP.Transport
        local function create_transport_factory(server_instructions)
          return function(args)
            local transport, tools = get_transport_and_tools(args.cfg.cmd[1])
            setup_mcp_init_expectations(transport, tools, server_instructions)
            return transport
          end
        end

        -- Default transport factory for tests
        Client.static.methods.new_transport.default = create_transport_factory()

        local adapter = {
          name = "test_adapter_for_mcp_tools",
          roles = { llm = "assistant", user = "user" },
          features = {},
          opts = { tools = true },
          url = "http://0.0.0.0",
          schema = { model = { default = "dummy" } },
          handlers = {
            response = {
              parse_chat = function(self, data, tools)
                for _, tool in ipairs(data.tools or {}) do
                  table.insert(tools, tool)
                end
                return {
                  status = "success",
                  output = { role = "assistant", content = data.content }
                }
              end
            },
            tools = {
              format_calls = function(self, llm_tool_calls)
                return llm_tool_calls
              end,
              format_response = function(self, llm_tool_call, mcp_output)
                return { role = "tool", content = mcp_output }
              end,
            }
          },
        }

        ---Create a chat buffer with MCP servers configured
        ---@param mcp_cfg? CodeCompanion.MCPConfig
        ---@return CodeCompanion.Chat
        function create_chat(mcp_cfg)
          mcp_cfg = mcp_cfg or {
            servers = {
              math_mcp = { cmd = { "math_mcp" } },
              other_mcp = { cmd = { "other_mcp" } },
            },
            opts = {
              default_servers = { "math_mcp", "other_mcp" },
            },
          }
          local loading = vim.tbl_count(mcp_cfg.servers)
          -- NOTE: We rely on this event to know when tools are loaded
          vim.api.nvim_create_autocmd("User", {
            pattern = "CodeCompanionMCPServerToolsLoaded",
            callback = function()
              loading = loading - 1
              return loading == 0
            end,
          })
          local chat = h.setup_chat_buffer({
            mcp = mcp_cfg,
            adapters = {
              http = { [adapter.name] = adapter },
            },
          }, { name = adapter.name })
          vim.wait(1000, function() return loading == 0 end)
          return chat
        end

        ---Extract tool output messages from chat messages
        ---@param chat_msgs table[]
        ---@return string[]
        function extract_tool_outputs(chat_msgs)
          return vim.iter(chat_msgs):map(function(msg)
            if msg.role == "tool" then
              return msg.content
            end
          end):totable()
        end
      ]])
    end,
    post_case = function()
      h.is_true(child.lua_get("MATH_MCP_TRANSPORT:all_handlers_consumed()"))
      h.is_true(child.lua_get("OTHER_MCP_TRANSPORT:all_handlers_consumed()"))
    end,
    post_once = child.stop,
  },
})

T["MCP Tools"] = MiniTest.new_set()

T["MCP Tools"]["MCP tools can be used as CodeCompanion tools"] = function()
  h.mock_http(child)
  h.queue_mock_http_response(child, {
    content = "Call some tools",
    tools = {
      { ["function"] = { name = "math_mcp_math_add", arguments = { a = 1, b = 3 } } },
      { ["function"] = { name = "math_mcp_math_mul", arguments = { a = 4, b = 2 } } },
      { ["function"] = { name = "math_mcp_math_add", arguments = { a = 2, b = -3 } } },
    },
  })
  local chat_msgs = child.lua([[
    local chat = create_chat()
    MATH_MCP_TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      local retval
      if params.name == "math_add" then
        retval = params.arguments.a + params.arguments.b
      elseif params.name == "math_mul" then
        retval = params.arguments.a * params.arguments.b
      else
        return "error", { code = -32601, message = "Unknown tool: " .. params.name }
      end
      return "result", {
        content = { { type = "text", text = tostring(retval) } }
      }
    end, { repeats = 3 })

    chat:add_buf_message({
      role = "user",
      content = "@{mcp:math_mcp} Use some tools.",
    })
    chat:submit()
    vim.wait(1000, function() return vim.bo[chat.bufnr].modifiable end)
    return chat.messages
  ]])

  local tool_output_msgs = vim
    .iter(chat_msgs)
    :map(function(msg)
      if msg.role == "tool" then
        return msg.content
      end
    end)
    :totable()
  h.eq({ "4", "8", "-1" }, tool_output_msgs)

  local llm_req = child.lua_get("_G.mock_client:get_last_request().payload")
  local has_prompt = vim.iter(llm_req.messages):any(function(msg)
    return msg.content:find("math_mcp")
      and msg.content:find("math_mcp_math_add")
      and msg.content:find("math_mcp_math_mul")
      and msg.content:find("Test MCP server instructions.")
  end)
  h.is_true(has_prompt)

  local math_mcp_tools = child.lua_get("MATH_MCP_TOOLS")
  local all_mcp_tools = child.lua_get("#MATH_MCP_TOOLS + #OTHER_MCP_TOOLS")
  local llm_tool_schemas = llm_req.tools[1]
  h.eq(all_mcp_tools, vim.tbl_count(llm_tool_schemas))
  for _, mcp_tool in ipairs(math_mcp_tools) do
    local cc_tool_name = "math_mcp_" .. mcp_tool.name
    local llm_tool_schema = llm_tool_schemas[string.format("<tool>%s</tool>", cc_tool_name)]
    h.eq(llm_tool_schema.type, "function")
    h.eq(llm_tool_schema["function"].name, cc_tool_name)
    h.eq(llm_tool_schema["function"].description, mcp_tool.description)
    h.eq(llm_tool_schema["function"].parameters, mcp_tool.inputSchema)
  end
end

T["MCP Tools"]["MCP tools should handle errors correctly"] = function()
  h.mock_http(child)
  h.queue_mock_http_response(child, {
    content = "Should fail",
    tools = {
      { ["function"] = { name = "other_mcp_make_list", arguments = { count = -1, item = "y" } } },
    },
  })

  local chat_msgs = child.lua([[
    local chat = create_chat()
    OTHER_MCP_TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      if params.name == "echo" then
        return "error", { code = -32603, message = "test jsonrpc error" }
      elseif params.name == "make_list" then
        if params.arguments.count < 0 then
          return "result", {
            isError = true,
            content = { { type = "text", text = "count must be non-negative" } },
          }
        end
        local list = {}
        for i = 1, params.arguments.count do
          table.insert(list, { type = "text", text = params.arguments.item })
        end
        return "result", { content = list }
      end
    end)

    chat:add_buf_message({ role = "user", content = "@{mcp.other_mcp} Should have errors" })
    chat:submit()
    vim.wait(1000, function() return vim.bo[chat.bufnr].modifiable end)
    return chat.messages
  ]])

  local tool_output_msgs = child.lua_get("extract_tool_outputs(...)", { chat_msgs })
  h.eq({ "MCP Tool execution failed:\ncount must be non-negative" }, tool_output_msgs)
end

T["MCP Tools"]["allows overriding tool options and behavior"] = function()
  h.mock_http(child)
  h.queue_mock_http_response(child, {
    content = "Call some tools",
    tools = {
      { ["function"] = { name = "other_mcp_say_hi" } },
      { ["function"] = { name = "other_mcp_make_list", arguments = { count = 3, item = "xyz" } } },
      { ["function"] = { name = "other_mcp_echo", arguments = { value = "ECHO REQ" } } },
    },
  })

  local result = child.lua([[
    require("tests.log")
    local chat = create_chat({
      servers = {
        other_mcp = {
          cmd = { "other_mcp" },
          server_instructions = function(orig)
            return orig .. "\nAdditional instructions for other_mcp."
          end,
          tool_defaults = {
            require_approval_before = true,
          },
          tool_overrides = {
            echo = {
              timeout = 100,
              output = {
                prompt = function(self, meta)
                  return "Custom confirmation prompt for echo tool: " .. self.args.value
                end,
              },
            },
            say_hi = {
              opts = {
                require_approval_before = false,
              },
              system_prompt = "TEST SYSTEM PROMPT FOR SAY_HI",
            },
            make_list = {
              output = {
                success = function(self, stdout, meta)
                  local output = vim.iter(stdout[#stdout]):map(function(block)
                    assert(block.type == "text")
                    return block.text
                  end):join(",")
                  meta.tools.chat:add_tool_output(self, output)
                end
              },
            },
          }
        },
      },
      opts = {
        default_servers = { "other_mcp" },
      },
    })

    OTHER_MCP_TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      assert(params.name == "say_hi")
      return "result", { content = { { type = "text", text = "Hello there!" } } }
    end)
    OTHER_MCP_TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      assert(params.name == "make_list")
      local content = {}
      for i = 1, params.arguments.count do
        table.insert(content, { type = "text", text = params.arguments.item })
      end
      return "result", { content = content }
    end)
    OTHER_MCP_TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      assert(params.name == "echo")
      return "result", { content = { { type = "text", text = params.arguments.value } } }
    end, { latency = 10 * 1000 })

    chat:add_buf_message({ role = "user", content = "@{mcp:other_mcp}" })

    local confirmations = {}
    local ui = require("codecompanion.utils.ui")
    ui.confirm = function(prompt, choices)
      table.insert(confirmations, prompt)
      for i, choice in ipairs(choices) do
        if choice:find("Allow once") then
          return i
        end
      end
      assert(false, "No 'Allow once' choice found")
    end

    chat:submit()
    vim.wait(1000, function() return vim.bo[chat.bufnr].modifiable end)
    return { chat_msgs = chat.messages, confirmations = confirmations }
  ]])

  local has_server_instructions = vim.iter(result.chat_msgs):any(function(msg)
    return msg.content:find("Test MCP server instructions.\nAdditional instructions for other_mcp.")
  end)
  h.is_true(has_server_instructions)

  local has_custom_tool_prompt = vim.iter(result.chat_msgs):any(function(msg)
    return msg.content:find("TEST SYSTEM PROMPT FOR SAY_HI")
  end)
  h.is_true(has_custom_tool_prompt)

  local tool_output_msgs = child.lua_get("extract_tool_outputs(...)", { result.chat_msgs })
  h.eq(tool_output_msgs, {
    "Hello there!",
    "xyz,xyz,xyz",
    "MCP Tool execution failed:\nMCP JSONRPC error: [-32603] Request timed out after 100 ms",
  })

  h.eq(#result.confirmations, 2)
  h.expect_contains("make_list", result.confirmations[1])
  h.eq(result.confirmations[2], "Custom confirmation prompt for echo tool: ECHO REQ")
end

T["MCP Tools"]["long output will be truncated in the chat buffer"] = function()
  h.mock_http(child)
  local output_prefix = "@LONG_OUTPUT_START@"
  local output_suffix = "@LONG_OUTPUT_END@"
  local output_elem = "\u{1F605}"
  local output = output_prefix .. string.rep(output_elem, 5000) .. output_suffix
  h.queue_mock_http_response(child, {
    content = "Call a tool",
    tools = {
      { ["function"] = { name = "other_mcp_echo", arguments = { value = output } } },
    },
  })

  local result = child.lua([[
    local chat = create_chat()
    OTHER_MCP_TRANSPORT:expect_jsonrpc_call("tools/call", function(params)
      return "result", {
        content = { { type = "text", text = params.arguments.value } }
      }
    end)

    chat:add_buf_message({ role = "user", content = "@{mcp.other_mcp} Please echo a long message." })
    chat:submit()
    vim.wait(1000, function() return vim.bo[chat.bufnr].modifiable end)
    return { chat_msgs = chat.messages, chat_bufnr = chat.bufnr }
  ]])

  -- Chat buffer should contain truncated output (prefix .. elem * n .. truncation-mark)
  local chat_buf_lines = child.api.nvim_buf_get_lines(result.chat_bufnr, 0, -1, false)
  local chat_buf_content = table.concat(chat_buf_lines, "\n")
  local truncated_output_regex =
    string.format([=[%s\(%s\)\+[[:space:][:punct:]]*\[truncated\]]=], output_prefix, output_elem)
  h.expect_truthy(vim.regex(truncated_output_regex):match_str(chat_buf_content))

  -- LLM should receive full output
  local tool_output_msgs = child.lua_get("extract_tool_outputs(...)", { result.chat_msgs })
  h.eq(#tool_output_msgs, 1)
  h.eq(tool_output_msgs[1], output)
end

return T
