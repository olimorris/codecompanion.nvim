local log = require("codecompanion.utils.log")

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
  log:debug("FuncExecutor:orchestrate %s", self.index)
  local action = self.executor.tool.request.action
  if type(action) == "table" and type(action[1]) == "table" then
    ---Process all actions in sequence without creating new execution chains
    ---@param idx number The index
    ---@param prev_input? any
    ---@return nil
    local function process_actions(idx, prev_input)
      if idx > #action then
        -- All actions processed, continue to next command
        return self.executor:execute(self.index + 1, prev_input)
      end

      -- Allow the action to call the next action directly, without calling `Executor:execute`
      self:run(self.cmd, action[idx], prev_input, function(output)
        process_actions(idx + 1, output)
      end)
    end

    process_actions(1, input)
  else
    self:run(self.cmd, action, input)
  end
end

---Run the tool's function
---@param cmd fun(self: CodeCompanion.Agent, actions: table, input: any)
---@param action table
---@param input? any
---@param callback? fun(output: any)
---@return nil
function FuncExecutor:run(cmd, action, input, callback)
  log:debug("FuncExecutor:run")
  local ok, output = pcall(function()
    return cmd(self.executor.agent, action, input)
  end)
  if not ok then
    return self.executor:error(action, output)
  end

  self.executor:success(action, output)

  if callback then
    callback(output)
  else
    return self.executor:execute(self.index + 1, output)
  end
end

return FuncExecutor
