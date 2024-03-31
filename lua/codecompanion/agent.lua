---@class CodeCompanion.Agent
local Agent = {}

---@class CodeCompanion.AgentArgs
---@field context table
---@field strategy string

---@param args table
---@return CodeCompanion.Agent
function Agent.new(args)
  return setmetatable(args, { __index = Agent })
end

---@param prompts table
function Agent:workflow(prompts)
  print("Agent:workflow")
end

return Agent
