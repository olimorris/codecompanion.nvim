local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        ReasoningAgentBase = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_agent_base').ReasoningAgentBase

        -- Mock the unified reasoning prompt to avoid dependency issues
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt'] = {
          generate = function(config)
            return string.format("Generated system prompt for %s", tostring(config))
          end
        }

        -- Helper to create a sample agent config
        function create_sample_agent_config()
          return {
            agent_type = "Test Agent",
            tool_name = "test_agent",
            description = "A test reasoning agent",
            actions = {
              test_action = function(args, agent_state)
                return {
                  status = "success",
                  data = string.format("Test action executed with arg: %s", args.test_param or "none")
                }
              end,
              error_action = function(args, agent_state)
                return {
                  status = "error",
                  data = "Test error message"
                }
              end,
              state_action = function(args, agent_state)
                agent_state.test_value = args.value or "default"
                return {
                  status = "success",
                  data = string.format("State set to: %s", agent_state.test_value)
                }
              end
            },
            validation_rules = {
              test_action = { "test_param" },
              error_action = {},
              state_action = { "value" }
            },
            parameters = {
              type = "object",
              properties = {
                action = {
                  type = "string",
                  description = "The action to perform"
                },
                test_param = {
                  type = "string",
                  description = "Required parameter for test_action"
                },
                value = {
                  type = "string",
                  description = "Value for state_action"
                }
              },
              required = { "action" },
              additionalProperties = false
            },
            system_prompt_config = function()
              return "test_config"
            end
          }
        end

        -- Helper to create mock tool instance
        function create_mock_tool_instance()
          return {
            args = {},
            schema = {}
          }
        end

        -- Helper to create mock chat
        function create_mock_chat()
          return {
            messages = {},
            add_tool_output = function(self, tool, output, formatted_output)
              table.insert(self.messages, {
                tool = tool,
                output = output,
                formatted_output = formatted_output
              })
            end
          }
        end

        -- Helper to create mock agent
        function create_mock_agent()
          return {
            chat = create_mock_chat()
          }
        end
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test state management
T["get_state creates new state for new agent type"] = function()
  child.lua([[
    state1 = ReasoningAgentBase.get_state("agent_type_1")
    state2 = ReasoningAgentBase.get_state("agent_type_2")
  ]])

  local state1 = child.lua_get("state1")
  local state2 = child.lua_get("state2")

  h.eq("table", type(state1))
  h.eq("table", type(state2))
  h.expect_truthy(state1.current_instance == nil or state1.current_instance == vim.NIL)
  h.expect_truthy(state1.session_id == nil or state1.session_id == vim.NIL)
  h.expect_truthy(state1.tool_instance == nil or state1.tool_instance == vim.NIL)
  h.eq("table", type(state1.sub_chats))
end

T["get_state returns same state for same agent type"] = function()
  child.lua([[
    state1 = ReasoningAgentBase.get_state("same_agent")
    state1.test_marker = "unique_value"

    state2 = ReasoningAgentBase.get_state("same_agent")
    same_reference = state2.test_marker == "unique_value"
  ]])

  local same_reference = child.lua_get("same_reference")

  h.eq(true, same_reference)
end

T["get_state maintains isolation between different agent types"] = function()
  child.lua([[
    state_a = ReasoningAgentBase.get_state("agent_a")
    state_b = ReasoningAgentBase.get_state("agent_b")

    state_a.test_value = "value_a"
    state_b.test_value = "value_b"

    isolation_check = {
      a_value = state_a.test_value,
      b_value = state_b.test_value,
      different = state_a.test_value ~= state_b.test_value
    }
  ]])

  local isolation_check = child.lua_get("isolation_check")

  h.eq("value_a", isolation_check.a_value)
  h.eq("value_b", isolation_check.b_value)
  h.eq(true, isolation_check.different)
end

-- Test validator creation and validation
T["create_validator validates required parameters"] = function()
  child.lua([[
    -- Test the internal validator creation
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

    rules = {
      action1 = { "param1", "param2" },
      action2 = {}
    }

    validator = create_validator(rules)

    -- Test valid case
    valid1, error1 = validator("action1", { param1 = "value1", param2 = "value2" })

    -- Test missing parameter
    valid2, error2 = validator("action1", { param1 = "value1" })

    -- Test action with no requirements
    valid3, error3 = validator("action2", {})

    -- Test unknown action
    valid4, error4 = validator("unknown", {})

    validation_results = {
      valid1 = valid1, error1 = error1,
      valid2 = valid2, error2 = error2,
      valid3 = valid3, error3 = error3,
      valid4 = valid4, error4 = error4
    }
  ]])

  local results = child.lua_get("validation_results")

  h.eq(true, results.valid1)
  h.expect_truthy(results.error1 == nil or results.error1 == vim.NIL)

  h.eq(false, results.valid2)
  h.expect_contains("param2 is required for action1", results.error2)

  h.eq(true, results.valid3)
  h.expect_truthy(results.error3 == nil or results.error3 == vim.NIL)

  h.eq(true, results.valid4) -- Unknown actions pass validation
end

-- Test tool definition creation
T["create_tool_definition creates valid tool structure"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)

    tool_structure = {
      name = tool_def.name,
      cmds_type = type(tool_def.cmds),
      cmds_count = #tool_def.cmds,
      schema_type = type(tool_def.schema),
      system_prompt_type = type(tool_def.system_prompt),
      handlers_type = type(tool_def.handlers),
      output_type = type(tool_def.output)
    }
  ]])

  local structure = child.lua_get("tool_structure")

  h.eq("agent", structure.name)
  h.eq("table", structure.cmds_type)
  h.eq(1, structure.cmds_count)
  h.eq("table", structure.schema_type)
  h.eq("function", structure.system_prompt_type)
  h.eq("table", structure.handlers_type)
  h.eq("table", structure.output_type)
end

T["create_tool_definition has correct schema structure"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)

    schema_info = {
      type = tool_def.schema.type,
      function_name = tool_def.schema["function"].name,
      function_description = tool_def.schema["function"].description,
      parameters_type = type(tool_def.schema["function"].parameters),
      strict = tool_def.schema["function"].strict
    }
  ]])

  local schema_info = child.lua_get("schema_info")

  h.eq("function", schema_info.type)
  h.eq("test_agent", schema_info.function_name)
  h.eq("A test reasoning agent", schema_info.function_description)
  h.eq("table", schema_info.parameters_type)
  h.eq(true, schema_info.strict)
end

T["create_tool_definition system_prompt function works"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)

    prompt = tool_def.system_prompt()
    prompt_type = type(prompt)
    prompt_length = #prompt
  ]])

  local prompt_type = child.lua_get("prompt_type")
  local prompt_length = child.lua_get("prompt_length")

  h.eq("string", prompt_type)
  h.expect_truthy(prompt_length > 0)
end

T["create_tool_definition system_prompt handles errors gracefully"] = function()
  child.lua([[
    config = create_sample_agent_config()
    -- Make system_prompt_config throw an error
    config.system_prompt_config = function()
      error("Test error")
    end

    tool_def = ReasoningAgentBase.create_tool_definition(config)
    prompt = tool_def.system_prompt()
  ]])

  local prompt = child.lua_get("prompt")

  h.eq("string", type(prompt))
  h.expect_contains("Test Agent", prompt)
  h.expect_contains("helpful AI assistant", prompt)
end

-- Test action handling
T["tool handles valid actions successfully"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    -- Execute the command function
    cmd_func = tool_def.cmds[1]
    result = cmd_func(tool_instance, {action = "test_action", test_param = "test_value"}, nil)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Test action executed", result.data)
  h.expect_contains("test_value", result.data)
end

T["tool handles error actions"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]
    result = cmd_func(tool_instance, {action = "error_action"}, nil)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Test error message", result.data)
end

T["tool rejects invalid actions"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]
    result = cmd_func(tool_instance, {action = "invalid_action"}, nil)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Invalid action 'invalid_action'", result.data)
  h.expect_contains("Valid actions:", result.data)
end

T["tool validates required parameters"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]
    result = cmd_func(tool_instance, {action = "test_action"}, nil) -- Missing test_param
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("test_param is required", result.data)
end

T["tool handles missing action handler"] = function()
  child.lua([[
    config = create_sample_agent_config()
    -- Remove the handler but keep validation rule
    config.actions.test_action = nil

    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]
    result = cmd_func(tool_instance, {action = "test_action", test_param = "value"}, nil)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("No handler found for action 'test_action'", result.data)
end

T["tool maintains agent state across calls"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]

    -- First call to set state
    result1 = cmd_func(tool_instance, {action = "state_action", value = "first_value"}, nil)

    -- Second call should maintain state
    state = ReasoningAgentBase.get_state("Test Agent")
    state_value = state.test_value
  ]])

  local result1 = child.lua_get("result1")
  local state_value = child.lua_get("state_value")

  h.eq("success", result1.status)
  h.expect_contains("first_value", result1.data)
  h.eq("first_value", state_value)
end

T["tool sets tool_instance in agent state"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()
    tool_instance.unique_marker = "test_marker"

    cmd_func = tool_def.cmds[1]
    result = cmd_func(tool_instance, {action = "test_action", test_param = "value"}, nil)

    state = ReasoningAgentBase.get_state("Test Agent")
    has_tool_instance = state.tool_instance ~= nil and state.tool_instance.unique_marker == "test_marker"
  ]])

  local has_tool_instance = child.lua_get("has_tool_instance")

  h.eq(true, has_tool_instance)
end

-- Test output handlers
T["create_output_handlers creates all required handlers"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")

    handler_info = {
      success_type = type(handlers.success),
      error_type = type(handlers.error),
      prompt_type = type(handlers.prompt),
      rejected_type = type(handlers.rejected)
    }
  ]])

  local handler_info = child.lua_get("handler_info")

  h.eq("function", handler_info.success_type)
  h.eq("function", handler_info.error_type)
  h.eq("function", handler_info.prompt_type)
  h.eq("function", handler_info.rejected_type)
end

T["success handler adds tool output to chat"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = { action = "test" } }
    stdout = { "line1", "line2", "line3" }

    handlers.success(mock_tool, agent, nil, stdout)

    chat_messages = agent.chat.messages
    output_added = #chat_messages > 0
    output_content = output_added and chat_messages[1].output or nil
  ]])

  local output_added = child.lua_get("output_added")
  local output_content = child.lua_get("output_content")

  h.eq(true, output_added)
  h.expect_contains("line1", output_content)
  h.expect_contains("line2", output_content)
  h.expect_contains("line3", output_content)
end

T["error handler adds error output to chat"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = { action = "test" } }
    stderr = { "error1", "error2" }

    handlers.error(mock_tool, agent, nil, stderr)

    chat_messages = agent.chat.messages
    output_added = #chat_messages > 0
    output_content = output_added and chat_messages[1].output or nil
  ]])

  local output_added = child.lua_get("output_added")
  local output_content = child.lua_get("output_content")

  h.eq(true, output_added)
  h.expect_contains("[ERROR]", output_content)
  h.expect_contains("Test Agent", output_content)
  h.expect_contains("error1", output_content)
  h.expect_contains("error2", output_content)
end

T["prompt handler returns formatted prompt"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = { action = "test_action" } }
    prompt_text = handlers.prompt(mock_tool, agent)
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("Use Test Agent", prompt_text)
  h.expect_contains("test_action", prompt_text)
end

T["prompt handler handles missing action gracefully"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = {} }
    prompt_text = handlers.prompt(mock_tool, agent)
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("Use Test Agent", prompt_text)
  h.expect_contains("unknown action", prompt_text)
end

T["prompt handler handles missing args gracefully"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = {}
    prompt_text = handlers.prompt(mock_tool, agent)
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("Use Test Agent", prompt_text)
  h.expect_contains("unknown", prompt_text)
end

T["rejected handler adds rejection message to chat"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = { action = "test_action" } }
    feedback = "User did not approve"

    handlers.rejected(mock_tool, agent, nil, feedback)

    chat_messages = agent.chat.messages
    output_added = #chat_messages > 0
    output_content = output_added and chat_messages[1].output or nil
  ]])

  local output_added = child.lua_get("output_added")
  local output_content = child.lua_get("output_content")

  h.eq(true, output_added)
  h.expect_contains("Test Agent", output_content)
  h.expect_contains("User declined", output_content)
  h.expect_contains("test_action", output_content)
  h.expect_contains("User did not approve", output_content)
end

T["rejected handler works without feedback"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = { action = "test_action" } }

    handlers.rejected(mock_tool, agent, nil, nil)

    chat_messages = agent.chat.messages
    output_added = #chat_messages > 0
    output_content = output_added and chat_messages[1].output or nil
  ]])

  local output_added = child.lua_get("output_added")
  local output_content = child.lua_get("output_content")

  h.eq(true, output_added)
  h.expect_contains("User declined", output_content)
  -- Should not contain feedback reference when none provided
  h.not_eq(nil, string.match(output_content, "User declined to execute test_action$"))
end

T["rejected handler works with empty feedback"] = function()
  child.lua([[
    handlers = ReasoningAgentBase.create_output_handlers("Test Agent")
    agent = create_mock_agent()

    mock_tool = { args = { action = "test_action" } }

    handlers.rejected(mock_tool, agent, nil, "")

    chat_messages = agent.chat.messages
    output_content = chat_messages[1].output
  ]])

  local output_content = child.lua_get("output_content")

  h.expect_contains("User declined", output_content)
  -- Should not contain feedback reference when empty
  h.not_eq(nil, string.match(output_content, "User declined to execute test_action$"))
end

-- Test on_exit handler
T["tool definition includes on_exit handler"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)

    has_on_exit = tool_def.handlers.on_exit ~= nil
    on_exit_type = type(tool_def.handlers.on_exit)
  ]])

  local has_on_exit = child.lua_get("has_on_exit")
  local on_exit_type = child.lua_get("on_exit_type")

  h.eq(true, has_on_exit)
  h.eq("function", on_exit_type)
end

T["on_exit handler executes without error"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)

    agent = create_mock_agent()

    -- Should not error
    success = pcall(function()
      tool_def.handlers.on_exit(agent)
    end)
  ]])

  local success = child.lua_get("success")

  h.eq(true, success)
end

-- Test integration scenarios
T["complete workflow with multiple actions"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]

    -- Execute multiple actions
    result1 = cmd_func(tool_instance, {action = "state_action", value = "initial"}, nil)
    result2 = cmd_func(tool_instance, {action = "test_action", test_param = "param1"}, nil)
    result3 = cmd_func(tool_instance, {action = "state_action", value = "updated"}, nil)

    -- Check final state
    state = ReasoningAgentBase.get_state("Test Agent")
    final_state_value = state.test_value

    workflow_results = {
      result1_status = result1.status,
      result2_status = result2.status,
      result3_status = result3.status,
      final_state = final_state_value
    }
  ]])

  local workflow_results = child.lua_get("workflow_results")

  h.eq("success", workflow_results.result1_status)
  h.eq("success", workflow_results.result2_status)
  h.eq("success", workflow_results.result3_status)
  h.eq("updated", workflow_results.final_state)
end

T["different agent types maintain separate states"] = function()
  child.lua([[
    config1 = create_sample_agent_config()
    config1.agent_type = "Agent Type 1"

    config2 = create_sample_agent_config()
    config2.agent_type = "Agent Type 2"

    tool_def1 = ReasoningAgentBase.create_tool_definition(config1)
    tool_def2 = ReasoningAgentBase.create_tool_definition(config2)

    tool_instance = create_mock_tool_instance()

    cmd_func1 = tool_def1.cmds[1]
    cmd_func2 = tool_def2.cmds[1]

    -- Set different values in each agent
    result1 = cmd_func1(tool_instance, {action = "state_action", value = "agent1_value"}, nil)
    result2 = cmd_func2(tool_instance, {action = "state_action", value = "agent2_value"}, nil)

    -- Check states are separate
    state1 = ReasoningAgentBase.get_state("Agent Type 1")
    state2 = ReasoningAgentBase.get_state("Agent Type 2")

    separation_test = {
      agent1_value = state1.test_value,
      agent2_value = state2.test_value,
      states_different = state1.test_value ~= state2.test_value
    }
  ]])

  local separation_test = child.lua_get("separation_test")

  h.eq("agent1_value", separation_test.agent1_value)
  h.eq("agent2_value", separation_test.agent2_value)
  h.eq(true, separation_test.states_different)
end

T["error handling preserves agent state"] = function()
  child.lua([[
    config = create_sample_agent_config()
    tool_def = ReasoningAgentBase.create_tool_definition(config)
    tool_instance = create_mock_tool_instance()

    cmd_func = tool_def.cmds[1]

    -- Set initial state
    result1 = cmd_func(tool_instance, {action = "state_action", value = "preserved_value"}, nil)

    -- Trigger error
    result2 = cmd_func(tool_instance, {action = "invalid_action"}, nil)

    -- Check state is preserved
    state = ReasoningAgentBase.get_state("Test Agent")
    state_preserved = state.test_value == "preserved_value"

    preservation_test = {
      initial_success = result1.status == "success",
      error_occurred = result2.status == "error",
      state_preserved = state_preserved
    }
  ]])

  local preservation_test = child.lua_get("preservation_test")

  h.eq(true, preservation_test.initial_success)
  h.eq(true, preservation_test.error_occurred)
  h.eq(true, preservation_test.state_preserved)
end

return T
