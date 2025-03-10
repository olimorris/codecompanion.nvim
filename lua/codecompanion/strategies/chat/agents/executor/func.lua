local log = require("codecompanion.utils.log")

---@class CodeCompanion.Agent.Executor.Func
---@field executor CodeCompanion.Agent.Executor
---@field func fun(self: CodeCompanion.Agent, actions: table, input: any)
---@field index number
local FuncExecutor = {}

---@param executor CodeCompanion.Agent.Executor
---@param func fun()
---@param index number
function FuncExecutor.new(executor, func, index)
  return setmetatable({
    executor = executor,
    func = func,
    index = index,
  }, { __index = FuncExecutor })
end

---Orchestrate the tool function
---@param input any
---@return nil
function FuncExecutor:orchestrate(input)
  log:debug("FuncExecutor:orchestrate %s", self.index)

  local action = self.executor.tool.request.action
  log:debug("Action: %s", action)

  if type(action) == "table" and vim.isarray(action) and action[1] ~= nil then
    -- Handle multiple functions in the cmds array
    self:process_action_array(action, input)
  else
    self:run(self.func, action, input, function(output)
      self:proceed_to_next(output)
    end)
  end
end

---Process an array of actions sequentially
---@param actions table Array of actions
---@param input any Input for the first action
---@return nil
function FuncExecutor:process_action_array(actions, input)
  local function process_actions(idx, prev_input)
    if idx > #actions then
      -- All actions processed, continue to next command
      return self:proceed_to_next(prev_input)
    end

    -- Process each action and chain them together
    self:run(self.func, actions[idx], prev_input, function(output)
      process_actions(idx + 1, output)
    end)
  end

  process_actions(1, input)
end

---Move to the next function in the command chain or finish execution
---@param output any The output from the previous function
---@return nil
function FuncExecutor:proceed_to_next(output)
  if self.index < #self.executor.tool.cmds then
    local next_func = self.executor.tool.cmds[self.index + 1]
    local next_executor = FuncExecutor.new(self.executor, next_func, self.index + 1)
    return next_executor:orchestrate(output)
  else
    self.executor:close()
    return self.executor:setup(output)
  end
end

---Run the tool's function
---@param func fun(self: CodeCompanion.Agent, actions: table, input: any):{status:"success"|"error", data:any}?
---@param action table
---@param input? any
---@param callback? fun(output: any)
---@return nil
function FuncExecutor:run(func, action, input, callback)
  log:debug("FuncExecutor:run")
  local ok, output = pcall(function()
    return func(self.executor.agent, action, input)
  end)
  if not ok then
    return self.executor:error(action, output)
  end
  if output.status == self.executor.agent.constants.STATUS_ERROR then
    return self.executor:error(action, output.data or "An error occurred")
  end

  self.executor:success(action, output.data)

  if callback then
    callback(output)
  end
end

return FuncExecutor
