local log = require("codecompanion.utils.log")

local CONSTANTS = {
  MESSAGES = {
    TOOL_ACCESS = "I'm giving you access to tools from an MCP server",
    TOOL_GROUPS = "Tools from MCP Server `%s`",
  },
}

local fmt = string.format

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
---@class CodeCompanion.Tool.MCPToolBridge: CodeCompanion.Tools.Tool
local tool_output = {
  ---@param self CodeCompanion.Tool.MCPToolBridge
  ---@param tools CodeCompanion.Tools
  ---@param cmd table The command that was executed
  ---@param stdout table The output from the command
  success = function(self, tools, cmd, stdout)
    local chat = tools.chat
    local output = M.format_tool_result_content(stdout and stdout[#stdout])
    local for_user = fmt(
      [[MCP: %s executed successfully:
````
%s
````]],
      self.name,
      output
    )
    chat:add_tool_output(self, output, for_user)
  end,

  ---@param self CodeCompanion.Tool.MCPToolBridge
  ---@param tools CodeCompanion.Tools
  ---@param cmd table
  ---@param stderr table The error output from the command
  error = function(self, tools, cmd, stderr)
    local chat = tools.chat
    local err_msg = M.format_tool_result_content(stderr and stderr[#stderr] or "<NO ERROR MESSAGE>")
    local for_user = fmt(
      [[MCP: %s failed:
````
%s
````
Arguments:
````%s
````]],
      self.name,
      err_msg,
      vim.inspect(self.args)
    )
    chat:add_tool_output(self, "MCP Tool execution failed:\n" .. err_msg, for_user)
  end,

  ---The message which is shared with the user when asking for their approval
  ---@param self CodeCompanion.Tool.MCPToolBridge
  ---@param tools CodeCompanion.Tools
  ---@return nil|string
  prompt = function(self, tools)
    return fmt("Execute the `%s` MCP tool?\nArguments:\n%s", self.name, vim.inspect(self.args))
  end,
}

---Build a CodeCompanion tool from an MCP tool specification
---@param client CodeCompanion.MCP.Client
---@param mcp_tool MCP.Tool
---@return string? tool_name
---@return table? tool_config
function M.build(client, mcp_tool)
  if mcp_tool.execution and mcp_tool.execution.taskSupport == "required" then
    return log:warn(
      "[MCP::Tool Bridge::%s] tool `%s` requires task execution support, which is not supported",
      client.name,
      mcp_tool.name
    )
  end

  local prefixed_name = fmt("%s_%s", client.name, mcp_tool.name)

  -- Users can override server options via tool configuration
  local override = (client.cfg.tool_overrides and client.cfg.tool_overrides[mcp_tool.name]) or {}
  local output_cb = vim.tbl_deep_extend("force", tool_output, override.output or {})
  local tool_opts = vim.tbl_deep_extend("force", client.cfg.tool_defaults or {}, override.opts or {})

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
      ---Execute the MCP tool
      ---@param self CodeCompanion.Tools
      ---@param args table The arguments from the LLM's tool call
      ---@param input? any The output from the previous function call
      ---@param output_handler function Async callback for completion
      ---@return nil|table
      function(self, args, input, output_handler)
        local chat_id = self.chat and self.chat.id or nil
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
        end, { timeout = override.timeout, chat_id = chat_id })
      end,
    },
    output = output_cb,
  }

  local tool_cfg = {
    description = mcp_tool.title or mcp_tool.name,
    callback = tool,
    enabled = override.enabled,
    -- User should use the generated tool group instead of individual tools
    visible = false,
    -- `_mcp_info` marks the tool as originating from an MCP server
    opts = { _mcp_info = { server = client.name } },
  }

  return prefixed_name, tool_cfg
end

---Setup tools from an MCP server into the MCP registry
---@param client CodeCompanion.MCP.Client
---@param mcp_tools MCP.Tool[]
---@return string[] tools
function M.setup_tools(client, mcp_tools)
  local mcp = require("codecompanion.mcp")
  local tools = {}
  local tool_configs = {}

  for _, tool in ipairs(mcp_tools) do
    local name, tool_cfg = M.build(client, tool)
    if name and tool_cfg then
      tool_configs[name] = tool_cfg
      table.insert(tools, name)
    end
  end

  if #tools == 0 then
    log:warn("[MCP::Tool Bridge::%s] has no valid tools to configure", client.name)
    return {}
  end

  local server_prompt = {
    fmt("%s `%s`: %s.", CONSTANTS.MESSAGES.TOOL_ACCESS, client.name, table.concat(tools, ", ")),
  }

  -- The prompt should also contain instructions from the server, if any.
  local server_instructions = client:get_server_instructions()
  if server_instructions and server_instructions ~= "" then
    table.insert(server_prompt, "Detailed instructions for this MCP server:")
    table.insert(server_prompt, server_instructions)
  end

  local group = {
    description = string.format("Tools from MCP Server `%s`", client.name),
    tools = tools,
    prompt = table.concat(server_prompt, "\n"),
    opts = { collapse_tools = true },
  }

  mcp.register_tools(client.name, tool_configs, group)

  return tools
end

return M
