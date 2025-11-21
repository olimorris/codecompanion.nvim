local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tools.Orchestrator.Runner
---@field orchestrator CodeCompanion.Tools.Orchestrator
---@field runner fun(self: CodeCompanion.Tools, actions: table, input: any)
---@field index number
---@field tool CodeCompanion.Tools.Tool Captured tool reference for this execution
local Runner = {}

---@param orchestrator CodeCompanion.Tools.Orchestrator
---@param runner fun()
---@param index number
---@param tool? CodeCompanion.Tools.Tool Optional tool reference to capture
function Runner.new(orchestrator, runner, index, tool)
  return setmetatable({
    orchestrator = orchestrator,
    runner = runner,
    index = index,
    tool = tool or orchestrator.tool,
  }, { __index = Runner })
end

---Setup the tool function
---@param input any
---@return nil
function Runner:setup(input)
  log:debug("Runner:setup %s", self.index)

  local args = self.tool.args
  log:debug("Args: %s", args)

  self:run(self.runner, args, input, function(output)
    self:proceed_to_next(output)
  end)
end

---Move to the next function in the command chain or finish execution
---@param output any The output from the previous function
---@return nil
function Runner:proceed_to_next(output)
  local current_tool = self.tool
  if not current_tool then
    self.orchestrator:close()
    return self.orchestrator:setup(output)
  end

  if self.index < #self.tool.cmds then
    local next_func = self.tool.cmds[self.index + 1]
    local next_executor = Runner.new(self.orchestrator, next_func, self.index + 1, self.tool)
    return next_executor:setup(output)
  else
    if not self.orchestrator.queue:is_empty() then
      local next_tool = self.orchestrator.queue:peek()
      local current_name = self.tool.name

      -- Option to only use the handlers once for successive executions of the same tool
      if next_tool and next_tool.name == current_name and next_tool.opts and next_tool.opts.use_handlers_once then
        self.orchestrator.tool = self.orchestrator.queue:pop()
        local next_func = self.orchestrator.tool.cmds[1]
        local next_executor = Runner.new(self.orchestrator, next_func, 1, self.orchestrator.tool)
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

    -- Temporarily set orchestrator.tool to captured tool for proper attribution
    local original_tool = self.orchestrator.tool
    self.orchestrator.tool = self.tool

    if msg.status == self.orchestrator.tools.constants.STATUS_ERROR then
      self.orchestrator:error(action, msg.data or "An error occurred")
      self.orchestrator:close()
      -- Restore after close completes
      self.orchestrator.tool = original_tool
      return
    end

    self.orchestrator:success(action, msg.data)
    -- Restore after success
    self.orchestrator.tool = original_tool

    if callback then
      callback(msg)
    end
  end

  local ok, output = pcall(function()
    return runner(self.orchestrator.tools, action, input, output_handler)
  end)
  if not ok then
    -- Swap tool for error attribution
    local original_tool = self.orchestrator.tool
    self.orchestrator.tool = self.tool
    self.orchestrator:error(action, output)
    self.orchestrator:close()
    -- Restore after close completes
    self.orchestrator.tool = original_tool
    return
  end

  if output ~= nil then
    -- otherwise async and should be called from within the runner
    output_handler(output)
  end
end

return Runner
