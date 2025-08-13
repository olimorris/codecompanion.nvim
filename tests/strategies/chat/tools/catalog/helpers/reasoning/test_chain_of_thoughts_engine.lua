local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        ChainOfThoughtEngine = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.chain_of_thoughts_engine')

        -- Mock the ReasoningVisualizer to avoid dependency issues in tests
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer'] = {
          visualize_chain = function(chain)
            return string.format("Visualized chain with %d steps for problem: %s", #(chain.steps or {}), chain.problem or "Unknown")
          end
        }

        -- Mock the unified reasoning prompt to avoid dependency issues
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt'] = {
          generate_for_reasoning = function(type)
            return string.format("System prompt for %s reasoning", type)
          end
        }

        -- Helper function to create a fresh agent state for each test
        function create_agent_state()
          return {}
        end
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test engine configuration
T["get_config returns valid configuration"] = function()
  child.lua([[
    config = ChainOfThoughtEngine.get_config()

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

  h.eq("Chain of Thoughts Agent", config_types.agent_type)
  h.eq("chain_of_thoughts_agent", config_types.tool_name)
  h.eq("string", config_types.description_type)
  h.eq("table", config_types.actions_type)
  h.eq("table", config_types.validation_rules_type)
  h.eq("table", config_types.parameters_type)
  h.eq("function", config_types.system_prompt_config_type)
end

T["get_config has correct validation rules"] = function()
  child.lua([[
    config = ChainOfThoughtEngine.get_config()
    rules = config.validation_rules
  ]])

  local rules = child.lua_get("rules")

  h.eq(1, #rules.initialize)
  h.eq("problem", rules.initialize[1])

  h.eq(3, #rules.add_step)
  h.expect_contains("step_id", table.concat(rules.add_step, " "))
  h.expect_contains("content", table.concat(rules.add_step, " "))
  h.expect_contains("step_type", table.concat(rules.add_step, " "))

  h.eq(0, #rules.view_chain)
  h.eq(0, #rules.reflect)
end

T["get_config has correct parameters structure"] = function()
  child.lua([[
    config = ChainOfThoughtEngine.get_config()
    params = config.parameters
  ]])

  local params = child.lua_get("params")

  h.eq("object", params.type)
  h.eq("table", type(params.properties))
  h.eq("table", type(params.required))
  h.eq("action", params.required[1])
  h.eq(false, params.additionalProperties)
end

-- Test initialize action
T["initialize creates new chain successfully"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)
  ]])

  local result = child.lua_get("result")
  local agent_state = child.lua_get("agent_state")

  h.eq("success", result.status)
  h.expect_contains("Test problem", result.data)
  h.expect_contains("CoT initialized", result.data)
  h.expect_contains("Session ID:", result.data)
  h.expect_contains("Actions available:", result.data)

  h.eq("string", type(agent_state.session_id))
  h.eq("table", type(agent_state.current_instance))
  h.eq("Test problem", agent_state.current_instance.problem)
  h.eq("Chain of Thought Agent", agent_state.current_instance.agent_type)
end

T["initialize rejects empty problem"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = ChainOfThoughtEngine.get_config().actions.initialize({problem = ""}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Problem description cannot be empty", result.data)
end

T["initialize rejects nil problem"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = ChainOfThoughtEngine.get_config().actions.initialize({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Problem description cannot be empty", result.data)
end

-- Test add_step action
T["add_step adds valid step successfully"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Analyze the problem",
      step_type = "analysis",
      reasoning = "We need to understand the requirements"
    }, agent_state)
  ]])

  local result = child.lua_get("result")
  local agent_state = child.lua_get("agent_state")

  h.eq("success", result.status)
  h.expect_contains("Added step 1", result.data)
  h.expect_contains("Analyze the problem", result.data)

  h.eq(1, #agent_state.current_instance.steps)
  h.eq("step1", agent_state.current_instance.steps[1].id)
  h.eq("Analyze the problem", agent_state.current_instance.steps[1].content)
  h.eq("analysis", agent_state.current_instance.steps[1].type)
  h.eq("We need to understand the requirements", agent_state.current_instance.steps[1].reasoning)
end

T["add_step works without reasoning parameter"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Simple step",
      step_type = "task"
    }, agent_state)
  ]])

  local result = child.lua_get("result")
  local agent_state = child.lua_get("agent_state")

  h.eq("success", result.status)
  h.eq("", agent_state.current_instance.steps[1].reasoning)
end

T["add_step rejects when no active chain"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Test content",
      step_type = "analysis"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active chain. Initialize first.", result.data)
end

T["add_step rejects empty content"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "",
      step_type = "analysis"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Step content cannot be empty", result.data)
end

T["add_step rejects nil content"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      step_type = "analysis"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Step content cannot be empty", result.data)
end

T["add_step rejects empty step_id"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "",
      content = "Test content",
      step_type = "analysis"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Step ID cannot be empty", result.data)
end

T["add_step rejects nil step_id"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      content = "Test content",
      step_type = "analysis"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("Step ID cannot be empty", result.data)
end

T["add_step rejects empty step_type"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Test content",
      step_type = ""
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Step type must be specified", result.data)
end

T["add_step rejects nil step_type"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Test content"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Step type must be specified", result.data)
end

T["add_step rejects duplicate step_id"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    -- Add first step
    ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "First step",
      step_type = "analysis"
    }, agent_state)

    -- Try to add second step with same ID
    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Second step",
      step_type = "reasoning"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Step ID 'step1' already exists", result.data)
end

T["add_step handles invalid step_type from underlying chain"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Test content",
      step_type = "invalid_type"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Invalid step type", result.data)
end

-- Test view_chain action
T["view_chain shows empty chain message"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.view_chain({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Chain initialized but no steps added yet", result.data)
  h.expect_contains("Test problem", result.data)
end

T["view_chain shows visualization when steps exist"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)
    ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "First step",
      step_type = "analysis"
    }, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.view_chain({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  -- The actual visualizer is being used, so check for its output format
  h.expect_contains("Test problem", result.data)
  h.expect_contains("Step 1", result.data)
  h.expect_contains("First step", result.data)
end

T["view_chain rejects when no active chain"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = ChainOfThoughtEngine.get_config().actions.view_chain({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active chain. Initialize first.", result.data)
end

-- Test reflect action
T["reflect analyzes chain with steps"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)
    ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Analyze problem",
      step_type = "analysis",
      reasoning = "Good reasoning"
    }, agent_state)
    ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step2",
      content = "Implement solution",
      step_type = "task"
    }, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.reflect({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Reflection Analysis", result.data)
  h.expect_contains("Total steps: 2", result.data)
  h.expect_contains("Insights:", result.data)
  h.expect_contains("Suggested Improvements:", result.data)
end

T["reflect includes user reflection when provided"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)
    ChainOfThoughtEngine.get_config().actions.add_step({
      step_id = "step1",
      content = "Test step",
      step_type = "analysis"
    }, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.reflect({
      reflection = "This was a good approach"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("User Reflection:", result.data)
  h.expect_contains("This was a good approach", result.data)
end

T["reflect rejects when no active chain"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = ChainOfThoughtEngine.get_config().actions.reflect({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active chain. Initialize first.", result.data)
end

T["reflect rejects when no steps to analyze"] = function()
  child.lua([[
    agent_state = create_agent_state()
    ChainOfThoughtEngine.get_config().actions.initialize({problem = "Test problem"}, agent_state)

    result = ChainOfThoughtEngine.get_config().actions.reflect({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No steps to reflect on. Add some steps first.", result.data)
end

-- Test action flow integration
T["complete workflow initialize -> add_step -> view_chain -> reflect"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = ChainOfThoughtEngine.get_config().actions

    -- Initialize
    init_result = actions.initialize({problem = "Solve math problem"}, agent_state)

    -- Add analysis step
    step1_result = actions.add_step({
      step_id = "analyze",
      content = "Break down the problem",
      step_type = "analysis",
      reasoning = "Need to understand what we're solving"
    }, agent_state)

    -- Add reasoning step
    step2_result = actions.add_step({
      step_id = "reason",
      content = "Apply mathematical principles",
      step_type = "reasoning",
      reasoning = "Use algebra to solve"
    }, agent_state)

    -- Add task step
    step3_result = actions.add_step({
      step_id = "implement",
      content = "Calculate the result",
      step_type = "task"
    }, agent_state)

    -- View chain
    view_result = actions.view_chain({}, agent_state)

    -- Reflect
    reflect_result = actions.reflect({
      reflection = "The solution process was systematic"
    }, agent_state)
  ]])

  local init_result = child.lua_get("init_result")
  local step1_result = child.lua_get("step1_result")
  local step2_result = child.lua_get("step2_result")
  local step3_result = child.lua_get("step3_result")
  local view_result = child.lua_get("view_result")
  local reflect_result = child.lua_get("reflect_result")
  local agent_state = child.lua_get("agent_state")

  -- All operations should succeed
  h.eq("success", init_result.status)
  h.eq("success", step1_result.status)
  h.eq("success", step2_result.status)
  h.eq("success", step3_result.status)
  h.eq("success", view_result.status)
  h.eq("success", reflect_result.status)

  -- Check final state
  h.eq(3, #agent_state.current_instance.steps)
  h.eq("Solve math problem", agent_state.current_instance.problem)
  h.expect_contains("systematic", reflect_result.data)
end

-- Test edge cases and error handling
T["handles agent_state modifications correctly"] = function()
  child.lua([[
    agent_state1 = create_agent_state()
    agent_state2 = create_agent_state()
    actions = ChainOfThoughtEngine.get_config().actions

    -- Initialize different chains in different states
    actions.initialize({problem = "Problem A"}, agent_state1)
    actions.initialize({problem = "Problem B"}, agent_state2)

    -- Add steps to each
    actions.add_step({
      step_id = "step1",
      content = "Step for A",
      step_type = "analysis"
    }, agent_state1)

    actions.add_step({
      step_id = "step1",
      content = "Step for B",
      step_type = "reasoning"
    }, agent_state2)
  ]])

  local agent_state1 = child.lua_get("agent_state1")
  local agent_state2 = child.lua_get("agent_state2")

  -- States should be independent
  h.eq("Problem A", agent_state1.current_instance.problem)
  h.eq("Problem B", agent_state2.current_instance.problem)
  h.eq("Step for A", agent_state1.current_instance.steps[1].content)
  h.eq("Step for B", agent_state2.current_instance.steps[1].content)
  h.eq("analysis", agent_state1.current_instance.steps[1].type)
  h.eq("reasoning", agent_state2.current_instance.steps[1].type)
end

T["system_prompt_config function works"] = function()
  child.lua([[
    config = ChainOfThoughtEngine.get_config()
    prompt = config.system_prompt_config()
  ]])

  local prompt = child.lua_get("prompt")

  h.eq("string", type(prompt))
  h.expect_contains("chain reasoning", prompt)
end

return T
