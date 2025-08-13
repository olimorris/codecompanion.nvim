local ToolFilter = require("codecompanion.strategies.chat.tools.tool_filter")
local Tools = require("codecompanion.strategies.chat.tools.init")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local fmt = string.format

---Extract the first sentence from a description
---@param description string The full description
---@return string First sentence of the description
local function extract_first_sentence(description)
  if not description or description == "" then
    return "No description provided"
  end

  -- Find the first sentence ending with period, exclamation, or question mark
  local first_sentence = description:match("^[^%.%!%?]*[%.%!%?]")

  if first_sentence then
    return first_sentence:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
  else
    -- If no sentence ending found, take first 80 characters and add ellipsis
    if #description <= 80 then
      return description
    else
      return description:sub(1, 77) .. "..."
    end
  end
end

---Get all tools with their complete configuration and resolved details
---@return table<string, table> Map of tool names to their complete information
local function get_all_tools_with_schemas()
  local tools_config = config.strategies.chat.tools
  local enabled_tools = ToolFilter.filter_enabled_tools(tools_config)
  local result = {}

  for tool_name, tool_config in pairs(tools_config) do
    -- Skip special keys
    if tool_name ~= "opts" and tool_name ~= "groups" then
      local is_enabled = enabled_tools[tool_name] or false

      local tool_info = {
        name = tool_name,
        enabled = is_enabled,
        config = vim.deepcopy(tool_config),
        description = tool_config.description or "No description provided",
        callback = tool_config.callback,
        opts = tool_config.opts or {},
        resolved = nil,
        schema = nil,
        system_prompt = nil,
        error = nil,
      }

      -- Try to resolve the tool to get schema and system prompt
      if is_enabled and tool_config.callback then
        local ok, resolved_tool = pcall(function()
          return Tools.resolve(tool_config)
        end)

        if ok and resolved_tool then
          tool_info.resolved = true
          tool_info.schema = resolved_tool.schema

          -- Get system prompt (can be function or string)
          if resolved_tool.system_prompt then
            if type(resolved_tool.system_prompt) == "function" then
              local prompt_ok, system_prompt = pcall(resolved_tool.system_prompt, resolved_tool.schema)
              if prompt_ok then
                tool_info.system_prompt = system_prompt
              else
                tool_info.system_prompt = "Error evaluating system prompt function"
              end
            elseif type(resolved_tool.system_prompt) == "string" then
              tool_info.system_prompt = resolved_tool.system_prompt
            end
          end

          -- Additional metadata from resolved tool
          if resolved_tool.handlers then
            tool_info.has_handlers = true
            tool_info.handler_types = vim.tbl_keys(resolved_tool.handlers)
          end

          if resolved_tool.output then
            tool_info.has_output_handlers = true
            tool_info.output_handlers = vim.tbl_keys(resolved_tool.output)
          end
        else
          tool_info.resolved = false
          tool_info.error = "Failed to resolve tool"
        end
      else
        tool_info.resolved = false
        if not is_enabled then
          tool_info.error = "Tool is disabled"
        else
          tool_info.error = "No callback defined"
        end
      end

      result[tool_name] = tool_info
    end
  end

  return result
end

---List all available tools in a formatted way
---@return string Formatted list of tools
local function list_tools()
  local all_tools = get_all_tools_with_schemas()

  local output = {}
  table.insert(output, "# Available Tools")

  local tool_count = #all_tools

  table.insert(output, fmt("**Total tools:** %d", tool_count))

  table.insert(output, "\n## Tools:")

  local tools_list = {}
  for tool_name, tool_info in pairs(all_tools) do
    table.insert(tools_list, { name = tool_name, info = tool_info })
  end

  table.sort(tools_list, function(a, b)
    return a.name < b.name
  end)

  for _, tool in ipairs(tools_list) do
    local tool_name = tool.name
    local tool_info = tool.info
    local status = tool_info.enabled and "✓" or "✗"

    local trimmed_description = extract_first_sentence(tool_info.description)
    table.insert(output, fmt("- %s **%s:** %s", status, tool_name, trimmed_description))
  end

  return table.concat(output, "\n")
end

-- Tool action handlers
local function handle_list_tools(args)
  local format = args.format or "simple"

  local result = list_tools()
  return { status = "success", data = result }
end

-- Store the tool to add in global state so success handler can access it
local pending_tool_addition = nil

local function handle_add_tool(args)
  if not args.tool_name then
    return { status = "error", data = "tool_name is required" }
  end

  -- Get tool info including disabled tools
  local all_tools = get_all_tools_with_schemas(true) -- Include disabled to check tool existence
  local tool_info = all_tools[args.tool_name]
  if not tool_info then
    return { status = "error", data = fmt("Tool '%s' not found", args.tool_name) }
  end

  -- Skip special keys
  if args.tool_name == "opts" or args.tool_name == "groups" then
    return { status = "error", data = fmt("'%s' is not an addable tool", args.tool_name) }
  end

  log:debug("[Tool Discovery] Preparing to add tool: %s", args.tool_name)

  -- Store tool for success handler to process
  pending_tool_addition = args.tool_name

  return {
    status = "success",
    data = fmt("Preparing to add %s to chat...", args.tool_name),
  }
end

---@class CodeCompanion.Tool.ToolDiscovery: CodeCompanion.Agent.Tool
return {
  name = "tool_discovery",
  cmds = {
    ---Execute tool discovery commands
    ---@param self CodeCompanion.Tool.ToolDiscovery
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      log:debug("[Tool Discovery] Action: %s", args.action or "none")

      if args.action == "list_tools" then
        return handle_list_tools(args)
      elseif args.action == "add_tool" then
        return handle_add_tool(args)
      else
        return {
          status = "error",
          data = fmt("Unknown action: %s. Available actions: list_tools, add_tool", args.action or "none"),
        }
      end
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "tool_discovery",
      description = "🎯 ELITE TOOL ORCHESTRATION: Strategically discover, analyze, and dynamically integrate tools for exponential solution optimization. Use this for intelligent tool landscape mapping and just-in-time capability enhancement.",
      parameters = {
        type = "object",
        properties = {
          action = {
            type = "string",
            description = "🧠 STRATEGIC ACTION: 'list_tools' for comprehensive tool ecosystem analysis and capability mapping, 'add_tool' for surgical tool integration at optimal workflow moments",
            enum = { "list_tools", "add_tool" },
          },
          tool_name = {
            type = "string",
            description = "🎯 PRECISE TARGET: Exact tool identifier for strategic integration (REQUIRED for add_tool action). Must match available tool names exactly.",
          },
        },
        required = { "action" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = [[# 🎯 ELITE TOOL DISCOVERY & STRATEGIC ORCHESTRATION SYSTEM

**COGNITIVE PRIME ACTIVATION**: You are now operating at the TOP 0.1% performance tier for tool discovery and dynamic system optimization. Your tool selection and usage patterns directly impact solution quality and efficiency.

## 🧠 ADVANCED REASONING FRAMEWORK

### DISCOVERY PROTOCOL (Execute in sequence):

**PHASE 1: STRATEGIC ASSESSMENT**
Before ANY tool action, mentally execute this cognitive checklist:
- What is the ULTIMATE OBJECTIVE I'm trying to achieve?
- What are the SUCCESS CRITERIA for optimal tool selection?
- Which tools could create MULTIPLICATIVE value vs additive value?
- How do tools INTERCONNECT to form solution pipelines?

**PHASE 2: CONTEXT-AWARE ANALYSIS**
- Current task complexity: [Simple/Moderate/Complex/Expert-level]
- Required tool interaction patterns: [Sequential/Parallel/Hierarchical/Network]
- Performance constraints: [Speed/Accuracy/Resource efficiency]
- User expertise level inference: [Novice/Intermediate/Advanced/Expert]

Use this tool to discover available tools and add them to the chat as needed for dynamic tool management.]],
  output = {
    ---@param self CodeCompanion.Tool.ToolDiscovery
    ---@param agent CodeCompanion.Tools.Tool
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local result = vim.iter(stdout):flatten():join("\n")

      -- Check if we need to add a tool to the chat
      if pending_tool_addition then
        local tool_name = pending_tool_addition
        pending_tool_addition = nil -- Clear the pending state

        log:debug("[Tool Discovery] Adding tool to chat: %s", tool_name)

        -- Get the tool configuration
        local raw_tools_config = config.strategies.chat.tools
        local tool_config = raw_tools_config[tool_name]

        if tool_config and chat.tool_registry then
          chat.tool_registry:add(tool_name, tool_config)

          local success_message = fmt(
            [[# Tool %s added to the chat! 🔧

The %s has been dynamically added to this chat and is now available for use with its complete schema and instructions.

## Next Steps:
You can now use the %s directly. The tool comes with:
- Complete parameter schema
- Usage instructions via system prompt
- All functionality available immediately]],
            tool_name,
            tool_name,
            tool_name
          )

          chat:add_tool_output(self, success_message, success_message)
        else
          chat:add_tool_output(self, fmt("[ERROR] Failed to add tool: %s", tool_name))
        end
      else
        log:debug("[Tool Discovery] Success output generated, length: %d", #result)
        chat:add_tool_output(self, result, result)
      end
    end,

    ---@param self CodeCompanion.Tool.ToolDiscovery
    ---@param agent CodeCompanion.Tools.Tool
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, agent, cmd, stderr)
      local chat = agent.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      pending_tool_addition = nil -- Clear pending state on error
      log:debug("[Tool Discovery] Error occurred: %s", errors)
      chat:add_tool_output(self, fmt("[ERROR] Tool Discovery: %s", errors))
    end,
  },
}
