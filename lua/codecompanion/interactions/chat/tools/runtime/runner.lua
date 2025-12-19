local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tools.Orchestrator.Runner
---@field cmd fun(self: CodeCompanion.Tools, actions: table, input: any)
---@field index number
---@field orchestrator CodeCompanion.Tools.Orchestrator
local Runner = {}

---@class CodeCompanion.Tools.Orchestrator.RunnerArgs
---@field cmd fun(self: CodeCompanion.Tools, actions: table, input: any)
---@field index number
---@field orchestrator CodeCompanion.Tools.Orchestrator

---@param args CodeCompanion.Tools.Orchestrator.RunnerArgs
function Runner.new(args)
  return setmetatable({
    cmd = args.cmd,
    index = args.index,
    orchestrator = args.orchestrator,
  }, { __index = Runner })
end

---Setup the tool function
---@param input any
---@return nil
function Runner:setup(input)
  log:debug("Runner:setup %s", self.index)

  local args = self.orchestrator.tool.args
  log:debug("Args: %s", args)

  self:run_tool(self.cmd, args, {
    input = input,
    callback = function(output)
      self:go_to_next_tool(output)
    end,
  })
end

---Move to the next function in the command chain or finish execution
---@param output any The output from the previous function
---@return nil
function Runner:go_to_next_tool(output)
  local current_tool = self.orchestrator.tool
  if not current_tool then
    self.orchestrator:finalize_tool()
    return self.orchestrator:setup_next_tool(output)
  end

  if self.index < #self.orchestrator.tool.cmds then
    local next_cmd = self.orchestrator.tool.cmds[self.index + 1]
    local next_runner = Runner.new({ index = self.index + 1, orchestrator = self.orchestrator, cmd = next_cmd })
    return next_runner:setup(output)
  else
    if not self.orchestrator.queue:is_empty() then
      local next_tool = self.orchestrator.queue:peek()
      local current_name = self.orchestrator.tool.name

      -- Option to only use the handlers once for successive executions of the same tool
      if next_tool and next_tool.name == current_name and next_tool.opts and next_tool.opts.use_handlers_once then
        self.orchestrator.tool = self.orchestrator.queue:pop()
        local next_cmd = self.orchestrator.tool.cmds[1]
        local next_runner = Runner.new({ index = 1, cmd = next_cmd, orchestrator = self.orchestrator })
        return next_runner:setup(output)
      end
    end
  end

  self.orchestrator:finalize_tool()
  return self.orchestrator:setup_next_tool(output)
end

---Run the tool's function
---@param cmd_func fun(self: CodeCompanion.Tools, actions: table, input: any, output_handler: fun(msg:{status:"success"|"error", data:any}):any):{status:"success"|"error", data:any}?
---@param action table
---@param args {input?: any, callback?: fun(output: any)}
---@return nil
function Runner:run_tool(cmd_func, action, args)
  log:debug("Runner:run")

  local tool_finished = false

  ---@param msg {status:"success"|"error", data:any}
  local function output_handler(msg)
    if tool_finished then
      return
    end
    tool_finished = true
    if msg.status == self.orchestrator.tools.constants.STATUS_ERROR then
      self.orchestrator:error({ action = action, error = msg.data or "An error occurred" })
      return
    end

    self.orchestrator:success({ action = action, output = msg.data })

    if args.callback then
      args.callback(msg)
    end
  end

  -- Set the current tool on the Tools object so tool functions can access the correct opts
  self.orchestrator.tools.tool = self.orchestrator.tool

  local ok, output = pcall(function()
    return cmd_func(self.orchestrator.tools, action, args.input, output_handler)
  end)
  if not ok then
    self.orchestrator:error({ action = action, error = output })
    return
  end

  if output ~= nil then
    -- Otherwise async and should be called from within the runner
    output_handler(output)
  end
end

return Runner
