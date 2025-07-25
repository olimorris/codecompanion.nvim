local ReasoningAgentBase =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_agent_base").ReasoningAgentBase
local GraphOfThoughtEngine =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.graph_of_thought_engine")

return ReasoningAgentBase.create_tool_definition(GraphOfThoughtEngine.get_config())
