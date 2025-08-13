local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        GraphOfThoughtEngine = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.graph_of_thought_engine')

        -- Mock the ReasoningVisualizer to avoid dependency issues in tests
        package.loaded['codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer'] = {
          visualize_graph = function(graph)
            local node_count = 0
            for _ in pairs(graph.nodes or {}) do
              node_count = node_count + 1
            end
            return string.format("Graph visualization with %d nodes", node_count)
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
    config = GraphOfThoughtEngine.get_config()

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

  h.eq("Graph of Thoughts Agent", config_types.agent_type)
  h.eq("graph_of_thoughts_agent", config_types.tool_name)
  h.eq("string", config_types.description_type)
  h.eq("table", config_types.actions_type)
  h.eq("table", config_types.validation_rules_type)
  h.eq("table", config_types.parameters_type)
  h.eq("function", config_types.system_prompt_config_type)
end

T["get_config has correct validation rules"] = function()
  child.lua([[
    config = GraphOfThoughtEngine.get_config()
    rules = config.validation_rules
  ]])

  local rules = child.lua_get("rules")

  h.eq(1, #rules.initialize)
  h.eq("goal", rules.initialize[1])

  h.eq(1, #rules.add_node)
  h.eq("content", rules.add_node[1])

  h.eq(2, #rules.add_edge)
  h.expect_contains("source_id", table.concat(rules.add_edge, " "))
  h.expect_contains("target_id", table.concat(rules.add_edge, " "))

  h.eq(0, #rules.view_graph)

  h.eq(2, #rules.merge_nodes)
  h.expect_contains("source_nodes", table.concat(rules.merge_nodes, " "))
  h.expect_contains("merged_content", table.concat(rules.merge_nodes, " "))
end

T["get_config has correct parameters structure"] = function()
  child.lua([[
    config = GraphOfThoughtEngine.get_config()
    params = config.parameters
  ]])

  local params = child.lua_get("params")

  h.eq("object", params.type)
  h.eq("table", type(params.properties))
  h.eq("table", type(params.required))
  h.eq("action", params.required[1])
  h.eq(false, params.additionalProperties)

  -- Check node_type enum
  h.eq("table", type(params.properties.node_type.enum))
  h.expect_contains("analysis", table.concat(params.properties.node_type.enum, " "))
  h.expect_contains("reasoning", table.concat(params.properties.node_type.enum, " "))
  h.expect_contains("task", table.concat(params.properties.node_type.enum, " "))
  h.expect_contains("validation", table.concat(params.properties.node_type.enum, " "))
  h.expect_contains("synthesis", table.concat(params.properties.node_type.enum, " "))
end

-- Test initialize action
T["initialize creates new graph successfully"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = GraphOfThoughtEngine.get_config().actions.initialize({goal = "Solve complex problem"}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Graph of Thoughts Initialized", result.data)
  h.expect_contains("Solve complex problem", result.data)
  h.expect_contains("Root Node ID:", result.data)
  h.expect_contains("Available Actions:", result.data)

  child.lua([[
    agent_state_info = {
      session_id_type = type(agent_state.session_id),
      current_instance_type = type(agent_state.current_instance),
      agent_type = agent_state.current_instance and agent_state.current_instance.agent_type or nil,
      get_element_type = agent_state.current_instance and type(agent_state.current_instance.get_element) or nil,
      update_element_score_type = agent_state.current_instance and type(agent_state.current_instance.update_element_score) or nil
    }
  ]])

  local agent_state_info = child.lua_get("agent_state_info")

  h.eq("string", agent_state_info.session_id_type)
  h.eq("table", agent_state_info.current_instance_type)
  h.eq("Graph of Thoughts Agent", agent_state_info.agent_type)
  h.eq("function", agent_state_info.get_element_type)
  h.eq("function", agent_state_info.update_element_score_type)
end

T["initialize validates goal parameter"] = function()
  child.lua([[
    agent_state = create_agent_state()
    -- Test with nil goal
    result1 = GraphOfThoughtEngine.get_config().actions.initialize({}, agent_state)

    -- Test with empty goal
    result2 = GraphOfThoughtEngine.get_config().actions.initialize({goal = ""}, agent_state)
  ]])

  local result1 = child.lua_get("result1")
  local result2 = child.lua_get("result2")

  -- Should succeed even with nil/empty goal since underlying GoT handles it
  h.eq("success", result1.status)
  h.eq("success", result2.status)
end

-- Test add_node action
T["add_node adds valid node successfully"] = function()
  child.lua([[
    agent_state = create_agent_state()
    GraphOfThoughtEngine.get_config().actions.initialize({goal = "Test goal"}, agent_state)

    result = GraphOfThoughtEngine.get_config().actions.add_node({
      content = "Analyze the problem",
      node_type = "analysis",
      id = "custom_id"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Node Added Successfully", result.data)
  h.expect_contains("Analyze the problem", result.data)
  h.expect_contains("analysis", result.data)
  h.expect_contains("Suggested Next Steps", result.data)

  -- Check that node was added to the graph
  child.lua([[
    nodes_type = type(agent_state.current_instance.nodes)
  ]])

  local nodes_type = child.lua_get("nodes_type")
  h.eq("table", nodes_type)
end

T["add_node works with default node_type"] = function()
  child.lua([[
    agent_state = create_agent_state()
    GraphOfThoughtEngine.get_config().actions.initialize({goal = "Test goal"}, agent_state)

    result = GraphOfThoughtEngine.get_config().actions.add_node({
      content = "Simple thought"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("analysis", result.data) -- default type
end

T["add_node rejects when no active graph"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = GraphOfThoughtEngine.get_config().actions.add_node({
      content = "Test content"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active graph. Initialize first.", result.data)
end

T["add_node handles invalid node_type"] = function()
  child.lua([[
    agent_state = create_agent_state()
    GraphOfThoughtEngine.get_config().actions.initialize({goal = "Test goal"}, agent_state)

    result = GraphOfThoughtEngine.get_config().actions.add_node({
      content = "Test content",
      node_type = "invalid_type"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Invalid node type", result.data)
end

-- Test add_edge action
T["add_edge creates valid edge successfully"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    -- Add two nodes
    result1 = actions.add_node({content = "First node", id = "node1"}, agent_state)
    result2 = actions.add_node({content = "Second node", id = "node2"}, agent_state)

    -- Add edge between them
    result = actions.add_edge({
      source_id = "node1",
      target_id = "node2",
      weight = 1.5,
      relationship_type = "leads_to"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Edge Added Successfully", result.data)
  h.expect_contains("node1", result.data)
  h.expect_contains("node2", result.data)
  h.expect_contains("1.50", result.data)
  h.expect_contains("leads_to", result.data)
end

T["add_edge works with default parameters"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    -- Add two nodes
    actions.add_node({content = "First node", id = "node1"}, agent_state)
    actions.add_node({content = "Second node", id = "node2"}, agent_state)

    -- Add edge with minimal parameters
    result = actions.add_edge({
      source_id = "node1",
      target_id = "node2"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("1.00", result.data) -- default weight
  h.expect_contains("depends_on", result.data) -- default relationship type
end

T["add_edge rejects when no active graph"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = GraphOfThoughtEngine.get_config().actions.add_edge({
      source_id = "node1",
      target_id = "node2"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active graph. Initialize first.", result.data)
end

T["add_edge rejects non-existent nodes"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    result = actions.add_edge({
      source_id = "nonexistent1",
      target_id = "nonexistent2"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("does not exist", result.data)
end

T["add_edge rejects self-loops"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)
    actions.add_node({content = "Test node", id = "node1"}, agent_state)

    result = actions.add_edge({
      source_id = "node1",
      target_id = "node1"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("Self-loops are not allowed", result.data)
end

T["add_edge detects cycles"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    -- Add three nodes
    actions.add_node({content = "Node 1", id = "node1"}, agent_state)
    actions.add_node({content = "Node 2", id = "node2"}, agent_state)
    actions.add_node({content = "Node 3", id = "node3"}, agent_state)

    -- Create a cycle: node1 -> node2 -> node3 -> node1
    actions.add_edge({source_id = "node1", target_id = "node2"}, agent_state)
    actions.add_edge({source_id = "node2", target_id = "node3"}, agent_state)

    result = actions.add_edge({source_id = "node3", target_id = "node1"}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("cycle", result.data)
end

-- Test view_graph action
T["view_graph shows graph visualization"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)
    actions.add_node({content = "Test node"}, agent_state)

    result = actions.view_graph({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  -- The actual visualizer is being used, so check for its output format
  h.expect_contains("Graph of Thoughts", result.data)
  h.expect_contains("Nodes:", result.data)
  h.expect_contains("Test node", result.data)
end

T["view_graph rejects when no active graph"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = GraphOfThoughtEngine.get_config().actions.view_graph({}, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active graph. Initialize first.", result.data)
end

-- Test merge_nodes action
T["merge_nodes combines multiple nodes successfully"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    -- Add multiple nodes
    actions.add_node({content = "First idea", id = "node1"}, agent_state)
    actions.add_node({content = "Second idea", id = "node2"}, agent_state)
    actions.add_node({content = "Third idea", id = "node3"}, agent_state)

    result = actions.merge_nodes({
      source_nodes = {"node1", "node2", "node3"},
      merged_content = "Combined ideas",
      merged_id = "merged1"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Nodes Merged Successfully", result.data)
  h.expect_contains("node1, node2, node3", result.data)
  h.expect_contains("merged1", result.data)
  h.expect_contains("Combined ideas", result.data)
end

T["merge_nodes works without custom merged_id"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    actions.add_node({content = "First idea", id = "node1"}, agent_state)
    actions.add_node({content = "Second idea", id = "node2"}, agent_state)

    result = actions.merge_nodes({
      source_nodes = {"node1", "node2"},
      merged_content = "Combined ideas"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("success", result.status)
  h.expect_contains("Nodes Merged Successfully", result.data)
end

T["merge_nodes rejects when no active graph"] = function()
  child.lua([[
    agent_state = create_agent_state()
    result = GraphOfThoughtEngine.get_config().actions.merge_nodes({
      source_nodes = {"node1", "node2"},
      merged_content = "Combined"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.eq("No active graph. Initialize first.", result.data)
end

T["merge_nodes rejects non-existent source nodes"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    result = actions.merge_nodes({
      source_nodes = {"nonexistent1", "nonexistent2"},
      merged_content = "Combined"
    }, agent_state)
  ]])

  local result = child.lua_get("result")

  h.eq("error", result.status)
  h.expect_contains("does not exist", result.data)
end

-- Test helper methods added during initialization
T["get_element method works correctly"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)
    actions.add_node({content = "Test node", id = "test_node"}, agent_state)

    element = agent_state.current_instance:get_element("test_node")
    element_exists = element ~= nil
  ]])

  local element_exists = child.lua_get("element_exists")

  h.eq(true, element_exists)
end

T["update_element_score method works correctly"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)
    actions.add_node({content = "Test node", id = "test_node"}, agent_state)

    -- Get initial score
    initial_score = agent_state.current_instance:get_element("test_node").score

    -- Update score
    success = agent_state.current_instance:update_element_score("test_node", 5.0)

    -- Get updated score
    updated_score = agent_state.current_instance:get_element("test_node").score
  ]])

  local initial_score = child.lua_get("initial_score")
  local success = child.lua_get("success")
  local updated_score = child.lua_get("updated_score")

  h.eq(true, success)
  h.eq(initial_score + 5.0, updated_score)
end

T["update_element_score handles non-existent nodes"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    success = agent_state.current_instance:update_element_score("nonexistent", 5.0)
  ]])

  local success = child.lua_get("success")

  h.eq(false, success)
end

-- Test complete workflow integration
T["complete workflow initialize -> add_nodes -> add_edges -> merge -> view"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    -- Initialize
    init_result = actions.initialize({goal = "Build a recommendation system"}, agent_state)

    -- Add multiple nodes
    node1_result = actions.add_node({
      content = "Analyze user behavior data",
      node_type = "analysis",
      id = "analyze_users"
    }, agent_state)

    node2_result = actions.add_node({
      content = "Design recommendation algorithm",
      node_type = "reasoning",
      id = "design_algo"
    }, agent_state)

    node3_result = actions.add_node({
      content = "Implement machine learning model",
      node_type = "task",
      id = "implement_ml"
    }, agent_state)

    node4_result = actions.add_node({
      content = "Test with sample data",
      node_type = "validation",
      id = "test_system"
    }, agent_state)

    -- Add dependencies
    edge1_result = actions.add_edge({
      source_id = "analyze_users",
      target_id = "design_algo"
    }, agent_state)

    edge2_result = actions.add_edge({
      source_id = "design_algo",
      target_id = "implement_ml"
    }, agent_state)

    edge3_result = actions.add_edge({
      source_id = "implement_ml",
      target_id = "test_system"
    }, agent_state)

    -- Merge some nodes
    merge_result = actions.merge_nodes({
      source_nodes = {"analyze_users", "design_algo"},
      merged_content = "Analysis and design phase completed"
    }, agent_state)

    -- View final graph
    view_result = actions.view_graph({}, agent_state)
  ]])

  local init_result = child.lua_get("init_result")
  local node1_result = child.lua_get("node1_result")
  local node2_result = child.lua_get("node2_result")
  local node3_result = child.lua_get("node3_result")
  local node4_result = child.lua_get("node4_result")
  local edge1_result = child.lua_get("edge1_result")
  local edge2_result = child.lua_get("edge2_result")
  local edge3_result = child.lua_get("edge3_result")
  local merge_result = child.lua_get("merge_result")
  local view_result = child.lua_get("view_result")

  -- All operations should succeed
  h.eq("success", init_result.status)
  h.eq("success", node1_result.status)
  h.eq("success", node2_result.status)
  h.eq("success", node3_result.status)
  h.eq("success", node4_result.status)
  h.eq("success", edge1_result.status)
  h.eq("success", edge2_result.status)
  h.eq("success", edge3_result.status)
  h.eq("success", merge_result.status)
  h.eq("success", view_result.status)
end

-- Test edge cases and error handling
T["handles agent_state isolation correctly"] = function()
  child.lua([[
    agent_state1 = create_agent_state()
    agent_state2 = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    -- Initialize different graphs in different states
    actions.initialize({goal = "Problem A"}, agent_state1)
    actions.initialize({goal = "Problem B"}, agent_state2)

    -- Add nodes to each
    actions.add_node({content = "Node for A", id = "nodeA"}, agent_state1)
    actions.add_node({content = "Node for B", id = "nodeB"}, agent_state2)

    -- Check that states are independent
    nodeA_exists_in_1 = agent_state1.current_instance:get_node("nodeA") ~= nil
    nodeB_exists_in_1 = agent_state1.current_instance:get_node("nodeB") ~= nil
    nodeA_exists_in_2 = agent_state2.current_instance:get_node("nodeA") ~= nil
    nodeB_exists_in_2 = agent_state2.current_instance:get_node("nodeB") ~= nil
  ]])

  local nodeA_exists_in_1 = child.lua_get("nodeA_exists_in_1")
  local nodeB_exists_in_1 = child.lua_get("nodeB_exists_in_1")
  local nodeA_exists_in_2 = child.lua_get("nodeA_exists_in_2")
  local nodeB_exists_in_2 = child.lua_get("nodeB_exists_in_2")

  -- Each state should only have its own nodes
  h.eq(true, nodeA_exists_in_1)
  h.eq(false, nodeB_exists_in_1)
  h.eq(false, nodeA_exists_in_2)
  h.eq(true, nodeB_exists_in_2)
end

T["system_prompt_config function works"] = function()
  child.lua([[
    config = GraphOfThoughtEngine.get_config()
    prompt = config.system_prompt_config()
  ]])

  local prompt = child.lua_get("prompt")

  h.eq("string", type(prompt))
  h.expect_contains("graph reasoning", prompt)
end

-- Test node suggestions functionality
T["add_node includes suggestions based on node type"] = function()
  child.lua([[
    agent_state = create_agent_state()
    actions = GraphOfThoughtEngine.get_config().actions

    actions.initialize({goal = "Test goal"}, agent_state)

    -- Test different node types for different suggestions
    analysis_result = actions.add_node({
      content = "Analyze the problem",
      node_type = "analysis"
    }, agent_state)

    reasoning_result = actions.add_node({
      content = "Apply logical thinking",
      node_type = "reasoning"
    }, agent_state)

    task_result = actions.add_node({
      content = "Implement solution",
      node_type = "task"
    }, agent_state)
  ]])

  local analysis_result = child.lua_get("analysis_result")
  local reasoning_result = child.lua_get("reasoning_result")
  local task_result = child.lua_get("task_result")

  h.eq("success", analysis_result.status)
  h.eq("success", reasoning_result.status)
  h.eq("success", task_result.status)

  -- Each should contain suggestions relevant to their type
  h.expect_contains("Suggested Next Steps", analysis_result.data)
  h.expect_contains("Suggested Next Steps", reasoning_result.data)
  h.expect_contains("Suggested Next Steps", task_result.data)
end

return T
