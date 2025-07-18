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

  local args = self.executor.tool.args
  log:debug("Args: %s", args)

  self:run(self.func, args, input, function(output)
    self:proceed_to_next(output)
  end)
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
    if not self.executor.queue:is_empty() then
      local next_tool = self.executor.queue:peek()
      local current_name = self.executor.tool.name

      -- Option to only use the handlers once for successive executions of the same tool
      if next_tool and next_tool.name == current_name and next_tool.opts and next_tool.opts.use_handlers_once then
        self.executor.tool = self.executor.queue:pop()
        local next_func = self.executor.tool.cmds[1]
        local next_executor = FuncExecutor.new(self.executor, next_func, 1)
        return next_executor:orchestrate(output)
      end
    end
  end

  self.executor:close()
  return self.executor:setup(output)
end

---Run the tool's function
---@param func fun(self: CodeCompanion.Agent, actions: table, input: any, output_handler: fun(msg:{status:"success"|"error", data:any}):any):{status:"success"|"error", data:any}?
---@param action table
---@param input? any
---@param callback? fun(output: any)
---@return nil
function FuncExecutor:run(func, action, input, callback)
  log:debug("FuncExecutor:run")

  local tool_finished = false

  ---@param msg {status:"success"|"error", data:any}
  local function output_handler(msg)
    if tool_finished then
      return log:info("output_handler for tool %s called more than once", self.executor.tool.name)
    end
    tool_finished = true
    if msg.status == self.executor.agent.constants.STATUS_ERROR then
      self.executor:error(action, msg.data or "An error occurred")
      return self.executor:close()
    end

    self.executor:success(action, msg.data)

    if callback then
      callback(msg)
    end
  end

  local ok, output = pcall(function()
    return func(self.executor.agent, action, input, output_handler)
  end)
  if not ok then
    self.executor:error(action, output)
    return self.executor:close()
  end

  if output ~= nil then
    -- otherwise async and should be called from within the func
    output_handler(output)
  end
end

return FuncExecutor
