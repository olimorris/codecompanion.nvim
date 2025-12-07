local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tools.Orchestrator.Runner
---@field orchestrator CodeCompanion.Tools.Orchestrator
---@field runner fun(self: CodeCompanion.Tools, actions: table, input: any)
---@field index number
local Runner = {}

---@param orchestrator CodeCompanion.Tools.Orchestrator
---@param runner fun()
---@param index number
function Runner.new(orchestrator, runner, index)
  return setmetatable({
    orchestrator = orchestrator,
    runner = runner,
    index = index,
  }, { __index = Runner })
end

---Setup the tool function
---@param input any
---@return nil
function Runner:setup(input)
  log:debug("Runner:setup %s", self.index)

  local args = self.orchestrator.tool.args
  log:debug("Args: %s", args)

  self:run(self.runner, args, input, function(output)
    self:proceed_to_next(output)
  end)
end

---Move to the next function in the command chain or finish execution
---@param output any The output from the previous function
---@return nil
function Runner:proceed_to_next(output)
  local current_tool = self.orchestrator.tool
  if not current_tool then
    self.orchestrator:close()
    return self.orchestrator:setup(output)
  end

  if self.index < #self.orchestrator.tool.cmds then
    local next_func = self.orchestrator.tool.cmds[self.index + 1]
    local next_executor = Runner.new(self.orchestrator, next_func, self.index + 1)
    return next_executor:setup(output)
  else
    if not self.orchestrator.queue:is_empty() then
      local next_tool = self.orchestrator.queue:peek()
      local current_name = self.orchestrator.tool.name

      -- Option to only use the handlers once for successive executions of the same tool
      if next_tool and next_tool.name == current_name and next_tool.opts and next_tool.opts.use_handlers_once then
        self.orchestrator.tool = self.orchestrator.queue:pop()
        local next_func = self.orchestrator.tool.cmds[1]
        local next_executor = Runner.new(self.orchestrator, next_func, 1)
        return next_executor:setup(output)
      end
    end
  end

  self.orchestrator:close()
  return self.orchestrator:setup(output)
end

---Run the tool's function
---@param runner fun(self: CodeCompanion.Tools, actions: table, input: any, output_handler: fun(msg:{status:"success"|"error", data:any}):any):{status:"success"|"error", data:any}?
---@param action table
---@param input? any
---@param callback? fun(output: any)
---@return nil
function Runner:run(runner, action, input, callback)
  log:debug("Runner:run")

  local tool_finished = false

  ---@param msg {status:"success"|"error", data:any}
  local function output_handler(msg)
    if tool_finished then
      return
    end
    tool_finished = true
    if msg.status == self.orchestrator.tools.constants.STATUS_ERROR then
      self.orchestrator:error(action, msg.data or "An error occurred")
      return self.orchestrator:close()
    end

    self.orchestrator:success(action, msg.data)

    if callback then
      callback(msg)
    end
  end

  local ok, output = pcall(function()
    return runner(self.orchestrator.tools, action, input, output_handler)
  end)
  if not ok then
    self.orchestrator:error(action, output)
    return self.orchestrator:close()
  end

  if output ~= nil then
    -- otherwise async and should be called from within the runner
    output_handler(output)
  end
end

return Runner
