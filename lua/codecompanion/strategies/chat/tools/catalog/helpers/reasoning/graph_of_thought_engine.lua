---@class CodeCompanion.GraphOfThoughtEngine

local GoT = require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.graph_of_thoughts")
local ReasoningVisualizer =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer")
local log = require("codecompanion.utils.log")
local fmt = string.format

local GraphOfThoughtEngine = {}

local Actions = {}

function Actions.initialize(args, agent_state)
  log:debug("[Graph of Thoughts Engine] Initializing with goal: %s", args.goal)

  agent_state.session_id = tostring(os.time())
  agent_state.current_instance = GoT.GraphOfThoughts.new()
  agent_state.current_instance.agent_type = "Graph of Thoughts Agent"

  agent_state.current_instance.get_element = function(self, id)
    return self:get_node(id)
  end

  agent_state.current_instance.update_element_score = function(self, id, boost)
    local node = self:get_node(id)
    if node then
      node.score = node.score + boost
      return true
    end
    return false
  end

  local goal_id = agent_state.current_instance:add_node(args.goal, "goal")

  return {
    status = "success",
    data = fmt(
      [[# Graph of Thoughts Initialized

**Goal:** %s
**Root Node ID:** %s

## Available Actions:
- **add_node**: Add new nodes to the graph
- **add_edge**: Create dependencies between nodes
- **view_graph**: Display the complete graph structure
- **merge_nodes**: Combine multiple nodes into one to synthesize new ideas

The graph is ready for complex multi-path reasoning with dependencies.]],
      args.goal,
      goal_id
    ),
  }
end

function Actions.add_node(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active graph. Initialize first." }
  end

  log:debug("[Graph of Thoughts Engine] Adding node: %s (type: %s)", args.content, args.node_type or "analysis")

  local node_id, error = agent_state.current_instance:add_node(args.content, args.id, args.node_type)

  if not node_id then
    return { status = "error", data = error }
  end

  local node = agent_state.current_instance:get_node(node_id)
  local suggestions = node:generate_suggestions()

  return {
    status = "success",
    data = fmt(
      [[# Node Added Successfully

**Node ID:** %s
**Content:** %s
**Type:** %s

The node has been added to the graph and is ready for dependency connections.

## Suggested Next Steps:

%s

Use 'add_edge' to create dependencies with other nodes.]],
      node_id,
      args.content,
      args.node_type or "analysis",
      table.concat(suggestions, "\n\n")
    ),
  }
end

function Actions.add_edge(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active graph. Initialize first." }
  end

  log:debug("[Graph of Thoughts Engine] Adding edge: %s -> %s", args.source_id, args.target_id)

  local success, error = agent_state.current_instance:add_edge(
    args.source_id,
    args.target_id,
    args.weight or 1.0,
    args.relationship_type or "depends_on"
  )

  if not success then
    return { status = "error", data = error }
  end

  if agent_state.current_instance:has_cycle() then
    return { status = "error", data = "Edge would create a cycle in the graph. Edge not added." }
  end

  return {
    status = "success",
    data = fmt(
      [[# Edge Added Successfully

**Source:** %s
**Target:** %s
**Weight:** %.2f
**Type:** %s

The dependency has been created. The target node will wait for the source node to complete before it can execute.]],
      args.source_id,
      args.target_id,
      args.weight or 1.0,
      args.relationship_type or "depends_on"
    ),
  }
end

function Actions.view_graph(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active graph. Initialize first." }
  end

  log:debug("[Graph of Thoughts Engine] Viewing graph structure")

  -- Use the new reasoning visualizer with sane defaults
  local graph_view = ReasoningVisualizer.visualize_graph(agent_state.current_instance)

  return {
    status = "success",
    data = graph_view,
  }
end

function Actions.merge_nodes(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active graph. Initialize first." }
  end

  log:debug("[Graph of Thoughts Engine] Merging nodes: %s", table.concat(args.source_nodes, ", "))

  local success, result =
    agent_state.current_instance:merge_nodes(args.source_nodes, args.merged_content, args.merged_id)

  if not success then
    return { status = "error", data = result }
  end

  return {
    status = "success",
    data = fmt(
      [[# Nodes Merged Successfully

**Source Nodes:** %s
**New Merged Node ID:** %s
**Content:** %s

The nodes have been combined into a single reasoning unit.]],
      table.concat(args.source_nodes, ", "),
      result,
      args.merged_content
    ),
  }
end

-- ============================================================================
-- ENGINE CONFIGURATION
-- ============================================================================
function GraphOfThoughtEngine.get_config()
  return {
    agent_type = "Graph of Thoughts Agent",
    tool_name = "graph_of_thoughts_agent",
    description = "Graph of Thoughts reasoning agent that systematically manages complex interconnected thought networks for comprehensive problem-solving.",
    actions = Actions,
    validation_rules = {
      initialize = { "goal" },
      add_node = { "content" },
      add_edge = { "source_id", "target_id" },
      view_graph = {},
      merge_nodes = { "source_nodes", "merged_content" },
    },
    parameters = {
      type = "object",
      properties = {
        action = {
          type = "string",
          description = "The graph action to perform: 'initialize', 'add_node', 'add_edge', 'view_graph', 'merge_nodes'",
        },
        goal = {
          type = "string",
          description = "The primary goal/problem to solve (required for 'initialize')",
        },
        content = {
          type = "string",
          description = "Content for the new node (required for 'add_node')",
        },
        node_type = {
          type = "string",
          enum = { "analysis", "reasoning", "task", "validation", "synthesis" },
          description = "Type of the node: analysis, reasoning, task, validation, or synthesis",
        },
        source_id = {
          type = "string",
          description = "Source node ID for edge creation (required for 'add_edge')",
        },
        target_id = {
          type = "string",
          description = "Target node ID for edge creation (required for 'add_edge')",
        },
        source_nodes = {
          type = "array",
          items = { type = "string" },
          description = "Array of source node IDs to merge (required for 'merge_nodes')",
        },
        merged_content = {
          type = "string",
          description = "Content for the new merged node (required for 'merge_nodes')",
        },
        merged_id = {
          type = "string",
          description = "Optional ID for the merged node (for 'merge_nodes')",
        },
      },
      required = { "action" },
      additionalProperties = false,
    },
    system_prompt_config = function()
      local UnifiedReasoningPrompt =
        require("codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt")
      return UnifiedReasoningPrompt.generate_for_reasoning("graph")
    end,
  }
end

return GraphOfThoughtEngine
