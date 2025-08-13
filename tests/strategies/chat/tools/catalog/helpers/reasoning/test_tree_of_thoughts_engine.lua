local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        TreeOfThoughtEngine = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.tree_of_thoughts_engine')

        -- Mock the ReasoningVisualizer to avoid dependency issues in tests
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer'] = {
          visualize_tree = function(root)
            if not root then
              return "Empty tree"
            end
            return string.format("# Tree of Thoughts\n\nRoot: %s", root.content or "Unknown")
          end
        }

        -- Mock the unified reasoning prompt to avoid dependency issues
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt'] = {
          generate_for_reasoning = function(type)
            return string.format("System prompt for %s reasoning", type)
          end
        }

        -- Global counter for unique IDs
        _global_counter = _global_counter or 0

        -- Mock the tree of thoughts module to control behavior
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.reasoning.tree_of_thoughts'] = {
          TreeOfThoughts = {
            new = function(self, problem)
              _global_counter = _global_counter + 1
              local instance_id = tostring(os.time()) .. "_" .. tostring(_global_counter)
              local actual_problem = problem or "Test Problem"
              return {
                instance_id = instance_id,
                problem = actual_problem,
                root = {
                  id = "root_id",
                  content = actual_problem,
                  children = {}
                },
                add_typed_thought = function(self, parent_id, content, node_type)
                  -- Handle error cases
                  if parent_id == "nonexistent" then
                    return nil, "Parent node not found: " .. parent_id
                  end

                  local new_node = {
                    id = string.format("node_%d", math.random(1000, 9999)),
                    content = content or "",
                    type = node_type or "analysis",
                    parent_id = parent_id
                  }

                  local suggestions = {
                    "🔍 Explore this further",
                    "🤔 Consider alternatives",
                    "📊 Gather more data",
                    "🔗 Connect to other ideas"
                  }

                  return new_node, nil, suggestions
                end,
                print_tree = function(self)
                  print("Tree structure for: " .. (self.problem or "Unknown"))
                  print("└── Root node")
                end
              }
            end
          }
        }

        -- Mock the log module to avoid dependency issues
        package.loaded['codecompanion.utils.log'] = {
          debug = function(self, message, ...)
            -- Silently ignore debug logs in tests
          end
        }

        -- Helper function to create a fresh agent state for each test
        function create_agent_state()
          return {}
        end

        -- Helper function to create mock agent state with tree instance
        function create_agent_state_with_tree(problem)
          local ToT = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.tree_of_thoughts')
          local state = create_agent_state()
          state.current_instance = ToT.TreeOfThoughts:new(problem)
          state.current_instance.agent_type = "Tree of Thoughts Agent"
          state.session_id = "test_session_123"
          return state
        end
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test engine configuration
T["get_config returns valid configuration"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()

    -- Extract the types we can test without transferring functions
    config_types = {
      agent_type = config.agent_type,
      tool_name = config.tool_name,
      description_type = type(config.description),
      actions_type = type(config.actions),
      validation_rules_type = type(config.validation_rules),
      parameters_type = type(config.parameters),
      system_prompt_config_type = type(config.system_prompt_config)
    }
  ]])

  local config_types = child.lua_get("config_types")

  h.eq("Tree of Thoughts Agent", config_types.agent_type)
  h.eq("tree_of_thoughts_agent", config_types.tool_name)
  h.eq("string", config_types.description_type)
  h.eq("table", config_types.actions_type)
  h.eq("table", config_types.validation_rules_type)
  h.eq("table", config_types.parameters_type)
  h.eq("function", config_types.system_prompt_config_type)
end

T["get_config has correct validation rules"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    rules = config.validation_rules
  ]])

  local rules = child.lua_get("rules")

  h.eq(1, #rules.initialize)
  h.eq("problem", rules.initialize[1])

  h.eq(1, #rules.add_thought)
  h.eq("content", rules.add_thought[1])

  h.eq(0, #rules.view_tree)
end

T["get_config has correct parameters structure"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    params = config.parameters
  ]])

  local params = child.lua_get("params")

  h.eq("object", params.type)
  h.eq("table", type(params.properties))
  h.eq("table", type(params.required))
  h.eq("action", params.required[1])
  h.eq(false, params.additionalProperties)
end

T["get_config system_prompt_config function works"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    prompt = config.system_prompt_config()
  ]])

  local prompt = child.lua_get("prompt")

  h.eq("string", type(prompt))
  h.expect_contains("tree reasoning", prompt)
end

-- Test initialize action
T["initialize action creates new tree instance"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    result = config.actions.initialize({problem = "Test problem"}, agent_state)

    result_info = {
      status = result.status,
      data_type = type(result.data),
      has_instance = agent_state.current_instance ~= nil,
      has_session_id = agent_state.session_id ~= nil,
      agent_type = agent_state.current_instance and agent_state.current_instance.agent_type or nil
    }
  ]])

  local result_info = child.lua_get("result_info")

  h.eq("success", result_info.status)
  h.eq("string", result_info.data_type)
  h.eq(true, result_info.has_instance)
  h.eq(true, result_info.has_session_id)
  h.eq("Tree of Thoughts Agent", result_info.agent_type)
end

T["initialize action returns formatted response"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    result = config.actions.initialize({problem = "Complex reasoning problem"}, agent_state)
    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Tree of Thoughts Initialized", data)
  h.expect_contains("Complex reasoning problem", data)
  h.expect_contains("Session ID:", data)
  h.expect_contains("The tree is ready", data)
end

T["initialize action adds interface methods"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    config.actions.initialize({problem = "Test problem"}, agent_state)

    interface_info = {
      has_get_element = type(agent_state.current_instance.get_element) == "function",
      has_update_element_score = type(agent_state.current_instance.update_element_score) == "function"
    }
  ]])

  local interface_info = child.lua_get("interface_info")

  h.eq(true, interface_info.has_get_element)
  h.eq(true, interface_info.has_update_element_score)
end

-- Test add_thought action
T["add_thought action requires active tree"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state() -- No tree instance

    result = config.actions.add_thought({content = "Test thought"}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("No active tree", result.data)
end

T["add_thought action adds thought successfully"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      content = "First analysis thought",
      type = "analysis",
      parent_id = "root"
    }, agent_state)

    result_info = {
      status = result.status,
      data_type = type(result.data)
    }
  ]])

  local result_info = child.lua_get("result_info")
  local result_data = child.lua_get("result.data")

  h.eq("success", result_info.status)
  h.eq("string", result_info.data_type)
  h.expect_contains("Added Analysis node", result_data)
  h.expect_contains("First analysis thought", result_data)
  h.expect_contains("Suggested next steps", result_data)
  h.expect_contains("Node ID:", result_data)
end

T["add_thought action defaults to analysis type"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      content = "Default type thought"
    }, agent_state)

    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Added Analysis node", data)
  h.expect_contains("Default type thought", data)
end

T["add_thought action defaults to root parent"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      content = "Root child thought",
      type = "reasoning"
    }, agent_state)

    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Added Reasoning node", data)
  h.expect_contains("Root child thought", data)
end

T["add_thought action validates node types"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    valid_result = config.actions.add_thought({
      content = "Valid thought",
      type = "validation"
    }, agent_state)

    invalid_result = config.actions.add_thought({
      content = "Invalid thought",
      type = "invalid_type"
    }, agent_state)

    validation_test = {
      valid_status = valid_result.status,
      invalid_status = invalid_result.status,
      invalid_error = invalid_result.data
    }
  ]])

  local validation_test = child.lua_get("validation_test")

  h.eq("success", validation_test.valid_status)
  h.eq("error", validation_test.invalid_status)
  h.expect_contains("Invalid type 'invalid_type'", validation_test.invalid_error)
  h.expect_contains("Valid types:", validation_test.invalid_error)
end

T["add_thought action handles all valid node types"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    types_test = {}
    valid_types = {"analysis", "reasoning", "task", "validation"}

    for _, node_type in ipairs(valid_types) do
      local result = config.actions.add_thought({
        content = "Test " .. node_type,
        type = node_type
      }, agent_state)

      types_test[node_type] = {
        status = result.status,
        contains_type = string.find(result.data, "Added " .. string.upper(node_type:sub(1,1)) .. node_type:sub(2) .. " node") ~= nil
      }
    end
  ]])

  local types_test = child.lua_get("types_test")

  for _, node_type in ipairs({ "analysis", "reasoning", "task", "validation" }) do
    h.eq("success", types_test[node_type].status)
    h.eq(true, types_test[node_type].contains_type)
  end
end

T["add_thought action includes suggestions in response"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      content = "Thought with suggestions",
      type = "task"
    }, agent_state)

    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Suggested next steps", data)
  h.expect_contains("🔍", data) -- Contains suggestion emojis
  h.expect_contains("Explore", data) -- Contains suggestion text
end

T["add_thought action includes node ID for further expansion"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      content = "Parent thought",
      type = "analysis"
    }, agent_state)

    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Node ID:", data)
  h.expect_contains("for adding child thoughts", data)
end

-- Test view_tree action
T["view_tree action requires active tree"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state() -- No tree instance

    result = config.actions.view_tree({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("No active tree", result.data)
end

T["view_tree action returns tree visualization"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Complex problem")

    result = config.actions.view_tree({}, agent_state)

    result_info = {
      status = result.status,
      data_type = type(result.data)
    }
  ]])

  local result_info = child.lua_get("result_info")
  local result_data = child.lua_get("result.data")

  h.eq("success", result_info.status)
  h.eq("string", result_info.data_type)
  h.expect_contains("Tree of Thoughts", result_data)
  h.expect_contains("Complex problem", result_data)
end

T["view_tree action uses visualizer when root exists"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Test problem")

    -- Ensure root exists
    agent_state.current_instance.root = {
      content = "Root content",
      children = {}
    }

    result = config.actions.view_tree({}, agent_state)
    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Tree of Thoughts", data)
  h.expect_contains("Root content", data)
end

T["view_tree action falls back to print_tree when no root"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Test problem")

    -- Remove root to trigger fallback
    agent_state.current_instance.root = nil

    result = config.actions.view_tree({}, agent_state)
    data = result.data
  ]])

  local data = child.lua_get("data")

  h.expect_contains("Tree structure", data)
  h.expect_contains("Root node", data)
end

-- Test edge cases and error handling
T["initialize action handles empty problem"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    result = config.actions.initialize({problem = ""}, agent_state)

    result_info = {
      status = result.status,
      has_instance = agent_state.current_instance ~= nil
    }
  ]])

  local result_info = child.lua_get("result_info")

  h.eq("success", result_info.status)
  h.eq(true, result_info.has_instance)
end

T["initialize action handles nil problem"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    result = config.actions.initialize({}, agent_state) -- No problem field

    result_info = {
      status = result.status,
      has_instance = agent_state.current_instance ~= nil
    }
  ]])

  local result_info = child.lua_get("result_info")

  h.eq("success", result_info.status)
  h.eq(true, result_info.has_instance)
end

T["add_thought action handles empty content"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      content = "",
      type = "analysis"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Added Analysis node", result.data)
end

T["add_thought action handles nil content"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    result = config.actions.add_thought({
      type = "reasoning"
    }, agent_state) -- No content field
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Added Reasoning node", result.data)
end

T["add_thought action handles invalid parent_id gracefully"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Root problem")

    -- The mock already handles invalid parent_id cases

    result = config.actions.add_thought({
      content = "Orphan thought",
      parent_id = "nonexistent"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Parent node not found", result.data)
end

-- Test complex workflows and integration
T["complete workflow: initialize, add thoughts, view tree"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    -- Step 1: Initialize
    init_result = config.actions.initialize({problem = "How to solve complex reasoning?"}, agent_state)

    -- Step 2: Add root analysis
    analysis_result = config.actions.add_thought({
      content = "Break down the problem into components",
      type = "analysis"
    }, agent_state)

    -- Step 3: Add reasoning thought
    reasoning_result = config.actions.add_thought({
      content = "Use systematic approach",
      type = "reasoning",
      parent_id = "root"
    }, agent_state)

    -- Step 4: Add task thought
    task_result = config.actions.add_thought({
      content = "Implement step-by-step solution",
      type = "task"
    }, agent_state)

    -- Step 5: View complete tree
    view_result = config.actions.view_tree({}, agent_state)

    workflow_results = {
      init_status = init_result.status,
      analysis_status = analysis_result.status,
      reasoning_status = reasoning_result.status,
      task_status = task_result.status,
      view_status = view_result.status,
      has_session = agent_state.session_id ~= nil,
      has_instance = agent_state.current_instance ~= nil
    }
  ]])

  local workflow_results = child.lua_get("workflow_results")

  h.eq("success", workflow_results.init_status)
  h.eq("success", workflow_results.analysis_status)
  h.eq("success", workflow_results.reasoning_status)
  h.eq("success", workflow_results.task_status)
  h.eq("success", workflow_results.view_status)
  h.eq(true, workflow_results.has_session)
  h.eq(true, workflow_results.has_instance)
end

T["multiple tree instances maintain basic separation"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()

    -- Create two separate agent states
    agent_state1 = create_agent_state()
    agent_state2 = create_agent_state()

    -- Initialize both with different problems
    result1 = config.actions.initialize({problem = "Problem 1"}, agent_state1)
    result2 = config.actions.initialize({problem = "Problem 2"}, agent_state2)

    independence_test = {
      both_successful = result1.status == "success" and result2.status == "success",
      both_have_instances = agent_state1.current_instance ~= nil and agent_state2.current_instance ~= nil,
      both_have_sessions = agent_state1.session_id ~= nil and agent_state2.session_id ~= nil,
      separate_states = agent_state1 ~= agent_state2
    }
  ]])

  local independence_test = child.lua_get("independence_test")

  h.eq(true, independence_test.both_successful)
  h.eq(true, independence_test.both_have_instances)
  h.eq(true, independence_test.both_have_sessions)
  h.eq(true, independence_test.separate_states)
end

T["error states don't affect agent state integrity"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state_with_tree("Robust problem")

    original_session = agent_state.session_id
    original_problem = agent_state.current_instance.problem

    -- Try various error operations
    error1 = config.actions.add_thought({content = "Bad thought", type = "invalid"}, agent_state)
    error2 = config.actions.add_thought({content = "Orphan", parent_id = "nonexistent"}, agent_state)

    -- Verify state is preserved
    integrity_test = {
      session_preserved = agent_state.session_id == original_session,
      problem_preserved = agent_state.current_instance.problem == original_problem,
      instance_still_exists = agent_state.current_instance ~= nil,
      error1_status = error1.status,
      error2_status = error2.status
    }
  ]])

  local integrity_test = child.lua_get("integrity_test")

  h.eq(true, integrity_test.session_preserved)
  h.eq(true, integrity_test.problem_preserved)
  h.eq(true, integrity_test.instance_still_exists)
  h.eq("error", integrity_test.error1_status)
  h.eq("error", integrity_test.error2_status)
end

T["reinitialize creates new tree instance"] = function()
  child.lua([[
    config = TreeOfThoughtEngine.get_config()
    agent_state = create_agent_state()

    -- Initial setup
    result1 = config.actions.initialize({problem = "Original problem"}, agent_state)
    first_instance = agent_state.current_instance
    config.actions.add_thought({content = "Original thought"}, agent_state)

    -- Reinitialize with new problem
    result2 = config.actions.initialize({problem = "New problem"}, agent_state)
    second_instance = agent_state.current_instance

    reinit_test = {
      first_success = result1.status == "success",
      second_success = result2.status == "success",
      has_instance_after_reinit = agent_state.current_instance ~= nil,
      has_session_after_reinit = agent_state.session_id ~= nil
    }
  ]])

  local reinit_test = child.lua_get("reinit_test")

  h.eq(true, reinit_test.first_success)
  h.eq(true, reinit_test.second_success)
  h.eq(true, reinit_test.has_instance_after_reinit)
  h.eq(true, reinit_test.has_session_after_reinit)
end

return T
