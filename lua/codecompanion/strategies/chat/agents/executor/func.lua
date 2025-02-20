---@class CodeCompanion.Agent.Executor.Func
---@field executor CodeCompanion.Agent.Executor
---@field cmd fun(self: CodeCompanion.Agent, actions: table, input: any)
---@field index number
local FuncExecutor = {}

---@param executor CodeCompanion.Agent.Executor
---@param cmd fun()
---@param index number
function FuncExecutor.new(executor, cmd, index)
  return setmetatable({
    executor = executor,
    cmd = cmd,
    index = index,
  }, { __index = FuncExecutor })
end

---Orchestrate the tool function
---@param input any
---@return nil
function FuncExecutor:orchestrate(input)
  local action = self.executor.tool.request.action
  -- Allow the cmds table to have multiple functions
  if type(action) == "table" and type(action[1]) == "table" then
    for _, a in ipairs(action) do
      self:run(self.cmd, a, input)
    end
  else
    self:run(self.cmd, action, input)
  end
end

---Run the tool function
---@param cmd fun(self: CodeCompanion.Agent, actions: table, input: any)
---@param action table
---@param input? any
function FuncExecutor:run(cmd, action, input)
  local ok, output = pcall(function()
    return cmd(self.executor.agent, action, input)
  end)
  if not ok then
    return self.executor:error(action, output)
  end
  self.executor:success(action, output)
  return self.executor:execute(self.index + 1, output)
end

return FuncExecutor
