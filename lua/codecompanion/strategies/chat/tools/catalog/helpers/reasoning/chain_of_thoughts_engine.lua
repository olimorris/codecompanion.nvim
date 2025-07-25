---@class CodeCompanion.ChainOfThoughtEngine

local ChainOfThought =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.chain_of_thoughts").ChainOfThought
local ReasoningVisualizer =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer")
local log = require("codecompanion.utils.log")
local fmt = string.format

local ChainOfThoughtEngine = {}

local Actions = {}

function Actions.initialize(args, agent_state)
  -- Validate problem parameter
  if not args.problem or args.problem == "" then
    return { status = "error", data = "Problem description cannot be empty" }
  end

  log:debug("[Chain of Thought Engine] Initializing session: %s", args.problem)

  agent_state.session_id = tostring(os.time())
  agent_state.current_instance = ChainOfThought.new(args.problem)
  agent_state.current_instance.agent_type = "Chain of Thought Agent"

  return {
    status = "success",
    data = fmt(
      "Chain of Thought initialized.\nProblem: %s\nSession ID: %s\n\nActions available:\n- add_step: Add step to chain\n- view_chain: See full chain\n- reflect: Analyze reasoning chain",
      args.problem,
      agent_state.session_id
    ),
  }
end

function Actions.add_step(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active chain. Initialize first." }
  end

  -- Enhanced validation
  if not args.content or args.content == "" then
    return { status = "error", data = "Step content cannot be empty" }
  end

  if not args.step_id or args.step_id == "" then
    return { status = "error", data = "Step ID cannot be empty" }
  end

  -- Check for duplicate step IDs
  for _, step in ipairs(agent_state.current_instance.steps) do
    if step.id == args.step_id then
      return { status = "error", data = fmt("Step ID '%s' already exists. Please use a unique ID.", args.step_id) }
    end
  end

  local success, message =
    agent_state.current_instance:add_step(args.step_type, args.content, args.reasoning or "", args.step_id)
  if not success then
    return { status = "error", data = message }
  end

  return {
    status = "success",
    data = fmt("Added step %d: %s", agent_state.current_instance.current_step, args.content),
  }
end

function Actions.view_chain(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active chain. Initialize first." }
  end

  if #agent_state.current_instance.steps == 0 then
    return {
      status = "success",
      data = fmt("Chain initialized but no steps added yet.\nProblem: %s", agent_state.current_instance.problem),
    }
  end

  log:debug("[Chain of Thought Engine] Viewing chain structure")

  local chain_view = ReasoningVisualizer.visualize_chain(agent_state.current_instance)

  return {
    status = "success",
    data = chain_view,
  }
end

function Actions.reflect(args, agent_state)
  if not agent_state.current_instance then
    return { status = "error", data = "No active chain. Initialize first." }
  end

  if #agent_state.current_instance.steps == 0 then
    return { status = "error", data = "No steps to reflect on. Add some steps first." }
  end

  local reflection_analysis = agent_state.current_instance:reflect()

  local output_parts = {}

  table.insert(output_parts, "## Reflection Analysis")
  table.insert(output_parts, fmt("Total steps: %d", reflection_analysis.total_steps))

  if #reflection_analysis.insights > 0 then
    table.insert(output_parts, "\n### Insights:")
    for _, insight in ipairs(reflection_analysis.insights) do
      table.insert(output_parts, fmt("• %s", insight))
    end
  end

  if #reflection_analysis.improvements > 0 then
    table.insert(output_parts, "\n### Suggested Improvements:")
    for _, improvement in ipairs(reflection_analysis.improvements) do
      table.insert(output_parts, fmt("• %s", improvement))
    end
  end

  if args.reflection and args.reflection ~= "" then
    table.insert(output_parts, fmt("\n### User Reflection:\n%s", args.reflection))
  end

  return {
    status = "success",
    data = table.concat(output_parts, "\n"),
  }
end

-- ============================================================================
-- ENGINE CONFIGURATION
-- ============================================================================
function ChainOfThoughtEngine.get_config()
  return {
    agent_type = "Chain of Thought Agent",
    tool_name = "chain_of_thoughts_agent",
    description = "Chain of Thought agent that follows sequential logical steps to solve complex problems systematically.",
    actions = Actions,
    validation_rules = {
      initialize = { "problem" },
      add_step = { "step_id", "content", "step_type" },
      view_chain = {},
      reflect = {},
    },
    parameters = {
      type = "object",
      properties = {
        action = {
          type = "string",
          description = "The reasoning action to perform: 'initialize', 'add_step', 'view_chain', 'reflect'",
        },
        problem = {
          type = "string",
          description = "The problem to solve using chain of thought reasoning (required for 'initialize' action)",
        },
        step_id = {
          type = "string",
          description = "Unique identifier for the reasoning step (required for 'add_step')",
        },
        content = {
          type = "string",
          description = "The reasoning step content or thought (required for 'add_step')",
        },
        step_type = {
          type = "string",
          description = "Type of reasoning step: 'analysis', 'reasoning', 'task', 'validation' (required for 'add_step')",
        },
        reasoning = {
          type = "string",
          description = "Detailed explanation of the reasoning behind this step (for 'add_step')",
        },
        reflection = {
          type = "string",
          description = "Reflection on the reasoning process and outcomes (optional for 'reflect')",
        },
      },
      required = { "action" },
      additionalProperties = false,
    },
    system_prompt_config = function()
      local UnifiedReasoningPrompt =
        require("codecompanion.strategies.chat.tools.catalog.helpers.unified_reasoning_prompt")
      return UnifiedReasoningPrompt.generate_for_reasoning("chain")
    end,
  }
end

return ChainOfThoughtEngine
