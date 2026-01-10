local log = require("codecompanion.utils.log")

local M = {}

---Format the output content from an MCP tool
---@param content string | MCP.ContentBlock[]
---@return string
function M.format_tool_result_content(content)
  if type(content) == "table" then
    if #content == 1 and content[1].type == "text" then
      return content[1].text
    end
    return vim.inspect(content)
  end
  return content or ""
end

---Default tool output callbacks that may be overridden by user config
local default_output = {
  success = function(self, tools, cmd, stdout)
    local chat = tools.chat
    local output = M.format_tool_result_content(stdout and stdout[#stdout])
    local args = vim.inspect(self.args)
    local for_user =
      string.format("MCP Tool [%s] executed successfully.\nArguments:\n%s\nOutput:\n%s", self.name, args, output)
    chat:add_tool_output(self, output, for_user)
  end,
  error = function(self, tools, cmd, stderr)
    local chat = tools.chat
    local err_msg = M.format_tool_result_content(stderr and stderr[#stderr] or "<NO ERROR MESSAGE>")
    local for_user = string.format(
      "MCP Tool [%s] execution failed.\nArguments:\n%s\nError Message:\n%s",
      self.name,
      vim.inspect(self.args),
      err_msg
    )
    chat:add_tool_output(self, "MCP Tool execution failed:\n" .. err_msg, for_user)
  end,
  prompt = function(self, tools)
    return string.format(
      "Please confirm to execute the MCP tool [%s] with arguments:\n%s",
      self.name,
      vim.inspect(self.args)
    )
  end,
}

---Build a CodeCompanion tool from an MCP tool specification
---@param client CodeCompanion.MCP.Client
---@param mcp_tool MCP.Tool
---@return string? tool_name
---@return table? tool_config
function M.build(client, mcp_tool)
  if mcp_tool.execution and mcp_tool.execution.taskSupport == "required" then
    log:warn("[MCP.%s] tool [%s] requires task execution support, which is not supported", client.name, mcp_tool.name)
    return nil
  end

  local prefixed_name = string.format("mcp_%s_%s", client.name, mcp_tool.name)
  local override = (client.cfg.tool_overrides and client.cfg.tool_overrides[mcp_tool.name]) or {}
  local tool_opts = vim.tbl_deep_extend("force", client.cfg.default_tool_opts or {}, override.opts or {})
  local output_callback = vim.tbl_deep_extend("force", default_output, override.output or {})

  local tool = {
    name = prefixed_name,
    opts = tool_opts,
    schema = {
      type = "function",
      ["function"] = {
        name = prefixed_name,
        description = mcp_tool.description,
        parameters = mcp_tool.inputSchema,
        strict = true,
      },
    },
    system_prompt = override.system_prompt,
    cmds = {
      function(self, args, input, output_handler)
        client:call_tool(mcp_tool.name, args, function(ok, result_or_error)
          local output
          if not ok then -- RPC failure
            output = { status = "error", data = result_or_error }
          else
            local result = result_or_error
            if result.isError then -- Tool execution error
              output = { status = "error", data = result.content }
            else
              output = { status = "success", data = result.content }
            end
          end
          output_handler(output)
        end, { timeout_ms = override.timeout_ms })
      end,
    },
    output = output_callback,
  }

  local tool_cfg = {
    description = mcp_tool.title or mcp_tool.name,
    callback = tool,
    enabled = override.enabled,
    -- user should use the generated tool group instead of individual tools
    visible = false,
    -- `_mcp_info` marks the tool as originating from an MCP server
    opts = { _mcp_info = { server = client.name } },
  }

  return prefixed_name, tool_cfg
end

---Setup tools from an MCP server into CodeCompanion
---@param client CodeCompanion.MCP.Client
---@param mcp_tools MCP.Tool[]
---@return string[] tools
function M.setup_tools(client, mcp_tools)
  local chat_tools = require("codecompanion.config").interactions.chat.tools
  local tools = {} ---@type string[]

  for _, tool in ipairs(mcp_tools) do
    local name, tool_cfg = M.build(client, tool)
    if name and tool_cfg then
      chat_tools[name] = tool_cfg
      table.insert(tools, name)
    end
  end

  if #tools == 0 then
    log:warn("[MCP.%s] has no valid tools to configure", client.name)
    return {}
  end

  -- The prompt should contain the list of tools.
  local server_prompt = {
    string.format("I'm giving you access to tools from MCP server '%s': %s.", client.name, table.concat(tools, ", ")),
  }

  -- The prompt should also contain instructions from the server, if any.
  local server_instructions = client:get_server_instructions()
  if server_instructions and server_instructions ~= "" then
    table.insert(server_prompt, "Detailed instructions of this MCP server:")
    table.insert(server_prompt, server_instructions)
  end

  chat_tools.groups[string.format("mcp.%s", client.name)] = {
    description = string.format("Tools from MCP Server '%s'", client.name),
    tools = tools,
    prompt = table.concat(server_prompt, "\n"),
    opts = { collapse_tools = true },
  }
  return tools
end

return M
