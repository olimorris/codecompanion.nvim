local CmdExecutor = require("codecompanion.strategies.chat.agents.executor.cmd")
local FuncExecutor = require("codecompanion.strategies.chat.agents.executor.func")
local Queue = require("codecompanion.strategies.chat.agents.executor.queue")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---@class CodeCompanion.Agent.Executor
---@field agent CodeCompanion.Agent
---@field current_cmd_tool table The current cmd tool that's being executed
---@field handlers table<string, function>
---@field id number The id of the agent
---@field index number The index of the current command
---@field output table<string, function>
---@field tool CodeCompanion.Agent.Tool
---@field queue CodeCompanion.Agent.Executor.Queue
---@field status string
local Executor = {}

---@param agent CodeCompanion.Agent
---@param id number
function Executor.new(agent, id)
  local self = setmetatable({
    agent = agent,
    current_cmd_tool = {},
    id = id,
    queue = Queue.new(),
  }, { __index = Executor })

  _G.codecompanion_cancel_tool = false

  return self
end

---Add the tool's handlers to the executor
---@return nil
function Executor:setup_handlers()
  self.handlers = {
    setup = function()
      vim.g.codecompanion_current_tool = self.tool.name
      if self.tool.handlers and self.tool.handlers.setup then
        self.tool.handlers.setup(self.agent)
      end
    end,
    on_exit = function()
      if self.tool.handlers and self.tool.handlers.on_exit then
        self.tool.handlers.on_exit(self.agent)
      end
    end,
  }

  self.output = {
    prompt = function(cmds)
      if self.tool.output and self.tool.output.prompt then
        return self.tool.output.prompt(self.agent, cmds)
      end
    end,
    rejected = function(cmd)
      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(self.agent, cmd)
      end
    end,
    error = function(cmd)
      if self.tool.output and self.tool.output.error then
        self.tool.output.error(self.agent, cmd, self.agent.stderr, self.agent.stdout or {})
      end
    end,
    success = function(cmd)
      if self.tool.output and self.tool.output.success then
        self.tool.output.success(self.agent, cmd, self.agent.stdout)
      end
    end,
  }
end

---When an agent is finished, finalize it via an autocmd
---@param self CodeCompanion.Agent.Executor
---@return nil
local function finalize_agent(self)
  return util.fire("AgentFinished", { id = self.id, bufnr = self.agent.bufnr })
end

---Setup the tool to be executed
---@param input? any
---@return nil
function Executor:setup(input)
  if self.queue:is_empty() then
    finalize_agent(self)
    return log:debug("Executor:execute - Queue empty")
  end
  if self.agent.status == self.agent.constants.STATUS_ERROR then
    finalize_agent(self)
    return log:debug("Executor:execute - Error")
  end

  -- Get the next tool to run
  self.tool = self.queue:pop()

  -- Setup the handlers
  self:setup_handlers()
  self.handlers.setup() -- Call this early as cmd_runner needs to setup its cmds dynamically

  -- Get the first command to run
  local cmd = self.tool.cmds[1]
  log:debug("Executor:execute - `%s` tool", self.tool.name)

  -- Check if the tool requires approval
  if self.tool.opts and self.tool.opts.requires_approval and not vim.g.codecompanion_auto_tool_mode then
    log:debug("Executor:execute - Asking for approval")

    local prompt = self.output.prompt(self.tool)
    if prompt == nil or prompt == "" then
      prompt = ("Run the %q tool?"):format(self.tool.name)
    end

    local ok, choice = pcall(vim.fn.confirm, prompt, "&Yes\n&No\n&Cancel")
    if not ok or choice == 0 or choice == 3 then -- Esc or Cancel
      log:debug("Executor:execute - Tool cancelled")
      finalize_agent(self)
      return self:close()
    end
    if choice == 1 then -- Yes
      log:debug("Executor:execute - Tool approved")
      self:execute(cmd, input)
    end
    if choice == 2 then -- No
      log:debug("Executor:execute - Tool rejected")
      self.output.rejected(cmd)
      return self:setup()
    end
  else
    self:execute(cmd, input)
  end
end

---Execute the tool command
---@param cmd string|table|function
---@param input? any
---@return nil
function Executor:execute(cmd, input)
  util.fire("ToolStarted", { id = self.id, tool = self.tool.name, bufnr = self.agent.bufnr })
  if type(cmd) == "function" then
    return FuncExecutor.new(self, cmd, 1):orchestrate(input)
  end
  return CmdExecutor.new(self, self.tool.cmds, 1):orchestrate()
end

---Handle an error from a tool
---@param action table
---@param error? string
---@return nil
function Executor:error(action, error)
  log:debug("Executor:error")
  self.agent.status = self.agent.constants.STATUS_ERROR
  if error then
    table.insert(self.agent.stderr, error)
    log:warn("Tool %s: %s", self.tool.name, error)
  end
  self.output.error(action)
  finalize_agent(self)
  self:close()
end

---Handle a successful completion of a tool
---@param action table
---@param output? string
---@return nil
function Executor:success(action, output)
  log:debug("Executor:success")
  self.agent.status = self.agent.constants.STATUS_SUCCESS
  if output then
    table.insert(self.agent.stdout, output)
  end
  self.output.success(action)
end

---Close the execution of the tool
---@return nil
function Executor:close()
  log:debug("Executor:close")
  self.handlers.on_exit()
  util.fire("ToolFinished", { id = self.id, name = self.tool.name, bufnr = self.agent.bufnr })
  self.agent.chat.subscribers:process(self.agent.chat)
  vim.g.codecompanion_current_tool = nil
end

return Executor
