local ReasoningAgentBase =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_agent_base").ReasoningAgentBase
local TreeOfThoughtEngine =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.tree_of_thoughts_engine")

return ReasoningAgentBase.create_tool_definition(TreeOfThoughtEngine.get_config())
