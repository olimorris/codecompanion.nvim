local ReasoningAgentBase =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_agent_base").ReasoningAgentBase
local ChainOfThoughtEngine =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.chain_of_thoughts_engine")

return ReasoningAgentBase.create_tool_definition(ChainOfThoughtEngine.get_config())
