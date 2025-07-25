---@class CodeCompanion.ReasoningAgentBase

local UnifiedReasoningPrompt = require("codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt")
local log = require("codecompanion.utils.log")
local fmt = string.format

local ReasoningAgentBase = {}
ReasoningAgentBase.__index = ReasoningAgentBase

local global_agent_states = {}

function ReasoningAgentBase.get_state(agent_type)
  if not global_agent_states[agent_type] then
    global_agent_states[agent_type] = {
      current_instance = nil,
      session_id = nil,
      tool_instance = nil,
      sub_chats = {},
    }
  end
  return global_agent_states[agent_type]
end

local function create_validator(action_rules)
  return function(action, args)
    local required = action_rules[action]
    if not required then
      return true
    end

    for _, param in ipairs(required) do
      if not args[param] then
        return false, param .. " is required for " .. action
      end
    end
    return true
  end
end

function ReasoningAgentBase.create_tool_definition(agent_config)
  local agent_type = agent_config.agent_type
  local actions = agent_config.actions
  local validation_rules = agent_config.validation_rules
  local system_prompt_config = agent_config.system_prompt_config

  local validator = create_validator(validation_rules)

  local function handle_action(args, tool_instance)
    log:debug("[%s] Handling action: %s", agent_type, args.action)

    local agent_state = ReasoningAgentBase.get_state(agent_type)
    agent_state.tool_instance = tool_instance

    -- Validate action and arguments
    local valid_actions = vim.tbl_keys(validation_rules)
    if not vim.tbl_contains(valid_actions, args.action) then
      return {
        status = "error",
        data = fmt("Invalid action '%s'. Valid actions: %s", args.action, table.concat(valid_actions, ", ")),
      }
    end

    local valid, error_msg = validator(args.action, args)
    if not valid then
      return { status = "error", data = error_msg }
    end

    -- Dispatch to action handler
    local handler = actions[args.action]
    if not handler then
      return { status = "error", data = fmt("No handler found for action '%s'", args.action) }
    end

    return handler(args, agent_state)
  end

  return {
    name = "agent",
    cmds = {
      function(self, args, input)
        log:debug("[%s] Tool invoked - action: %s", agent_type, args.action or "nil")
        local result = handle_action(args, self)
        log:debug("[%s] Command completed - status: %s", agent_type, result.status)
        return result
      end,
    },
    schema = {
      type = "function",
      ["function"] = {
        name = agent_config.tool_name,
        description = agent_config.description,
        parameters = agent_config.parameters,
        strict = true,
      },
    },
    system_prompt = function()
      local success, result = pcall(function()
        return UnifiedReasoningPrompt.generate(system_prompt_config())
      end)
      if success then
        return result
      else
        log:error("[%s] Failed to generate system prompt: %s", agent_type, result)
        return "You are a helpful AI assistant specialized in " .. agent_type .. "."
      end
    end,
    handlers = {
      on_exit = function(agent)
        local agent_state = ReasoningAgentBase.get_state(agent_type)
        log:debug("[%s] Session ended - session: %s", agent_type, agent_state.session_id or "none")
      end,
    },
    output = ReasoningAgentBase.create_output_handlers(agent_type),
  }
end

function ReasoningAgentBase.create_output_handlers(agent_type)
  return {
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local result = vim.iter(stdout):flatten():join("\n")
      local llm_output = fmt("%s", result)
      log:debug("[%s] Success output generated - output_length: %d", agent_type, #result)
      chat:add_tool_output(self, llm_output, llm_output)
    end,

    error = function(self, agent, cmd, stderr)
      local chat = agent.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      local agent_state = ReasoningAgentBase.get_state(agent_type)
      log:debug("[%s] Error occurred - session: %s", agent_type, agent_state.session_id or "none")
      log:debug("[%s] Error details: %s", agent_type, errors)
      local error_output = fmt("[ERROR] %s: %s", agent_type, errors)
      chat:add_tool_output(self, error_output)
    end,

    prompt = function(self, agent)
      log:debug(
        "[%s] Prompting user for approval - action: %s",
        agent_type,
        self.args and self.args.action or "unknown"
      )
      return fmt("Use %s (%s)?", agent_type, self.args and self.args.action or "unknown action")
    end,

    rejected = function(self, agent, cmd, feedback)
      local chat = agent.chat
      log:debug(
        "[%s] User rejected execution - action: %s, feedback: %s",
        agent_type,
        self.args and self.args.action or "unknown",
        feedback or "none"
      )
      local message = fmt("%s: User declined to execute %s", agent_type, self.args and self.args.action or "action")
      if feedback and feedback ~= "" then
        message = message .. fmt(" with feedback: %s", feedback)
      end
      chat:add_tool_output(self, message)
    end,
  }
end

return {
  ReasoningAgentBase = ReasoningAgentBase,
}
