local log = require("codecompanion.utils.log")

local M = {}

---Default tool output callbacks
local DefaultOutputCallbacks = {}

function DefaultOutputCallbacks.success(self, tools, cmd, stdout)
  local chat = tools.chat
  local output = stdout and stdout[#stdout]
  local args = vim.inspect(self.args)
  local for_user =
    string.format("MCP Tool [%s] executed successfully.\nArguments:\n%s\nOutput:\n%s", self.name, args, output)
  chat:add_tool_output(self, output, for_user)
end

function DefaultOutputCallbacks.error(self, tools, cmd, stderr)
  local chat = tools.chat
  local err_msg = stderr and stderr[#stderr] or "<NO ERROR MESSAGE>"
  local for_user = string.format(
    "MCP Tool [%s] execution failed.\nArguments:\n%s\nError Message:\n%s",
    self.name,
    vim.inspect(self.args),
    err_msg
  )
  chat:add_tool_output(self, "MCP Tool execution failed:\n" .. err_msg, for_user)
end

function DefaultOutputCallbacks.prompt(self, tools)
  return string.format(
    "Please confirm to execute the MCP tool [%s] with arguments:\n%s",
    self.name,
    vim.inspect(self.args)
  )
end

---Build a CodeCompanion tool from an MCP tool specification
---@param client CodeCompanion.MCP.Client
---@param mcp_tool MCP.Tool
---@return string|nil tool_name
---@return table|nil tool_config
function M.build(client, mcp_tool)
  if mcp_tool.execution and mcp_tool.execution.taskSupport == "required" then
    log:error("[MCP.%s] tool [%s] requires task execution support, which is not supported", client.name, mcp_tool.name)
    return nil
  end

  local prefixed_name = string.format("%s_%s", client.name, mcp_tool.name)
  local override = (client.cfg.tool_overrides and client.cfg.tool_overrides[mcp_tool.name]) or {}
  local tool_opts = vim.tbl_deep_extend("force", client.cfg.default_tool_opts or {}, override.opts or {})
  local output_callback = vim.tbl_deep_extend("force", DefaultOutputCallbacks, override.output or {})

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
          if not ok then
            log:error("[MCP.%s] tool [%s] call failed: %s", client.name, prefixed_name, result_or_error)
            output = { status = "error", data = result_or_error }
          else
            local result = result_or_error
            local output_str
            if result and result.content and #result.content == 1 and result.content[1].type == "text" then
              output_str = result.content[1].text -- just a single text block, make it simple
            else
              output_str = vim.inspect(result.content)
            end
            if result.isError then
              log:error("[MCP.%s] tool [%s] call returned error: %s", client.name, prefixed_name, output_str)
              output = { status = "error", data = output_str }
            else
              log:debug("[MCP.%s] tool [%s] call returned success: %s", client.name, prefixed_name, output_str)
              output = { status = "success", data = output_str }
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

---Install tools from an MCP server into CodeCompanion
---@param client CodeCompanion.MCP.Client
---@param mcp_tools MCP.Tool[]
---@return string[] tools
function M.install_tools(client, mcp_tools)
  local chat_tools = require("codecompanion.config").interactions.chat.tools
  local installed_tools = {} ---@type string[]

  for _, tool in ipairs(mcp_tools) do
    local name, tool_cfg = M.build(client, tool)
    if name and tool_cfg then
      chat_tools[name] = tool_cfg
      table.insert(installed_tools, name)
    end
  end

  if #installed_tools == 0 then
    log:info("[MCP.%s] has no valid tools to configure", client.name)
    return {}
  end

  local server_prompts = {
    string.format(
      "I'm giving you access to tools from MCP server '%s': %s.",
      client.name,
      table.concat(installed_tools, ", ")
    ),
  }

  local cfg_server_instr = client.cfg.server_instructions
  local final_server_instructions
  if type(cfg_server_instr) == "function" then
    final_server_instructions = cfg_server_instr(client.server_instructions)
  elseif type(cfg_server_instr) == "string" then
    final_server_instructions = cfg_server_instr
  else
    final_server_instructions = client.server_instructions
  end

  if final_server_instructions and final_server_instructions ~= "" then
    table.insert(server_prompts, "Detailed instructions of this MCP server:")
    table.insert(server_prompts, final_server_instructions)
  end

  chat_tools.groups[client.name] = {
    description = string.format("Tools from MCP Server '%s'", client.name),
    tools = installed_tools,
    prompt = table.concat(server_prompts, "\n"),
    opts = { collapse_tools = true },
  }
  return installed_tools
end

return M
