---@class CodeCompanion.TreeOfThoughtEngine

local ReasoningVisualizer =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer")
local ToT = require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.tree_of_thoughts")
local log = require("codecompanion.utils.log")
local fmt = string.format

local TreeOfThoughtEngine = {}

local Actions = {}

function Actions.initialize(args, agent_state)
  log:debug("[Tree of Thoughts Engine] Initializing with problem: %s", args.problem)

  agent_state.session_id = tostring(os.time())
  agent_state.current_instance = ToT.TreeOfThoughts:new(args.problem)
  agent_state.current_instance.agent_type = "Tree of Thoughts Agent"

  -- Add interface methods for base class compatibility
  agent_state.current_instance.get_element = function(self, id)
    if self.nodes then
      for _, node in ipairs(self.nodes) do
        if node.id == id then
          return node
        end
      end
    end
    return nil
  end

  agent_state.current_instance.update_element_score = function(self, id, boost)
    local node = self:get_element(id)
    if node then
      node.value = (node.value or 0) + boost
      return true
    end
    return false
  end

  return {
    status = "success",
    data = fmt(
      [[# Tree of Thoughts Initialized

**Problem:** %s
**Session ID:** %s

The tree is ready to explore multiple reasoning paths for your problem.]],
      args.problem,
      agent_state.session_id
    ),
  }
end

function Actions.add_thought(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active tree. Initialize first." }
  end

  local content = args.content
  local node_type = args.type or "analysis" -- Default to analysis
  local parent_id = args.parent_id or "root"

  log:debug("[Tree of Thoughts Engine] Adding typed thought: %s (%s)", content, node_type)

  -- Validate type
  local valid_types = { "analysis", "reasoning", "task", "validation" }
  if not vim.tbl_contains(valid_types, node_type) then
    return {
      status = "error",
      data = "Invalid type '" .. node_type .. "'. Valid types: " .. table.concat(valid_types, ", "),
    }
  end

  local new_node, error_msg, suggestions = agent_state.current_instance:add_typed_thought(parent_id, content, node_type)

  if not new_node then
    return { status = "error", data = error_msg }
  end

  -- Format the response with suggestions
  local response_data = fmt(
    [[**Added %s node:** %s

**💡 Suggested next steps:**
%s

**Node ID:** %s (for adding child thoughts)]],
    string.upper(node_type:sub(1, 1)) .. node_type:sub(2),
    content,
    table.concat(suggestions, "\n"),
    new_node.id
  )

  return {
    status = "success",
    data = response_data,
  }
end

function Actions.view_tree(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active tree. Initialize first." }
  end

  log:debug("[Tree of Thoughts Engine] Viewing tree structure")

  local tree_view = ""

  -- If we have a root node, visualize from there
  if agent_state.current_instance.root then
    tree_view = ReasoningVisualizer.visualize_tree(agent_state.current_instance.root)
  else
    -- Fallback to original method if no root
    local tree_lines = {}
    local original_print = print
    print = function(line)
      table.insert(tree_lines, line or "")
    end

    agent_state.current_instance:print_tree()
    print = original_print

    tree_view = table.concat(tree_lines, "\n")
  end

  return {
    status = "success",
    data = tree_view,
  }
end

function TreeOfThoughtEngine.get_config()
  return {
    agent_type = "Tree of Thoughts Agent",
    tool_name = "tree_of_thoughts_agent",
    description = "Tree of Thoughts reasoning agent that systematically explores multiple solution paths for complex problems.",
    actions = Actions,
    validation_rules = {
      initialize = { "problem" },
      add_thought = { "content" },
      view_tree = {},
    },
    parameters = {
      type = "object",
      properties = {
        action = {
          type = "string",
          description = "The tree action to perform: 'initialize', 'add_thought', 'view_tree'",
        },
        problem = {
          type = "string",
          description = "The problem to solve using tree of thoughts (required for 'initialize' action)",
        },
        content = {
          type = "string",
          description = "The thought content to add (required for 'add_thought')",
        },
        type = {
          type = "string",
          description = "Node type: 'analysis', 'reasoning', 'task', 'validation' (default: 'analysis', for 'add_thought')",
        },
        parent_id = {
          type = "string",
          description = "ID of parent node to add thought to (default: 'root', for 'add_thought')",
        },
      },
      required = { "action" },
      additionalProperties = false,
    },
    system_prompt_config = function()
      local UnifiedReasoningPrompt =
        require("codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt")
      return UnifiedReasoningPrompt.generate_for_reasoning("tree")
    end,
  }
end

return TreeOfThoughtEngine
