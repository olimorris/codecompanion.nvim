local CmdExecutor = require("codecompanion.strategies.chat.agents.executor.cmd")
local FuncExecutor = require("codecompanion.strategies.chat.agents.executor.func")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---@class CodeCompanion.Agent.Executor
---@field agent CodeCompanion.Agent
---@field current_cmd_tool table The current cmd tool that's being executed
---@field handlers table<string, function>
---@field index number The index of the current command
---@field output table<string, function>
---@field tool CodeCompanion.Agent.Tool
---@field status string
local Executor = {}

---@param agent CodeCompanion.Agent
---@param tool CodeCompanion.Agent.Tool
function Executor.new(agent, tool)
  log:debug("Executor.new: %s", tool.name)

  local self = setmetatable({
    agent = agent,
    current_cmd_tool = {},
    tool = tool,
  }, { __index = Executor })

  self.handlers = {
    setup = function()
      vim.g.codecompanion_current_tool = self.tool.name
      if self.tool.handlers and self.tool.handlers.setup then
        self.tool.handlers.setup(agent)
      end
    end,
    approved = function(cmd)
      if self.tool.handlers and self.tool.handlers.approved then
        return self.tool.handlers.approved(agent, cmd)
      end
      return true
    end,
    on_exit = function()
      if self.tool.handlers and self.tool.handlers.on_exit then
        self.tool.handlers.on_exit(agent)
      end
    end,
  }

  self.output = {
    rejected = function(cmd)
      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(agent, cmd)
      end
    end,
    error = function(cmd, error, output)
      if self.tool.output and self.tool.output.error then
        self.tool.output.error(agent, cmd, error, output)
      end
    end,
    success = function(cmd, output)
      if self.tool.output and self.tool.output.success then
        self.tool.output.success(agent, cmd, output)
      end
    end,
  }

  _G.codecompanion_cancel_tool = false
  util.fire("AgentStarted", { tool = tool.name, bufnr = agent.bufnr })
  self.handlers.setup()

  return self
end

---Execute the tool command
---@param index? number The index of the command to execute
---@param input? any
---@return nil
function Executor:execute(index, input)
  index = index or 1
  log:debug("Executor:execute %s", index)
  if
    not self.tool.cmds
    or index > vim.tbl_count(self.tool.cmds)
    or self.agent.status == self.agent.constants.STATUS_ERROR
  then
    return self:close()
  end

  local cmd = self.tool.cmds[index]
  if type(cmd) == "function" then
    return FuncExecutor.new(self, cmd, index):orchestrate(input)
  end
  return CmdExecutor.new(self, cmd):orchestrate()
end

---Does the tool require approval before it can be executed?
---@return boolean
function Executor:requires_approval()
  return config.strategies.chat.agents.tools[self.tool.name].opts
      and config.strategies.chat.agents.tools[self.tool.name].opts.user_approval
    or false
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
    log:error("Error running %s: %s", self.tool.name, error)
  end
  self.output.error(action, self.agent.stderr, self.agent.stdout)
  self:close()
end

---Handle a successful completion of a tool
---@param action table
---@param output? string
---@return nil
function Executor:success(action, output)
  log:debug("Executor:success")
  if output then
    table.insert(self.agent.stdout, output)
  end
  self.output.success(action, self.agent.stdout)
end

---Close the execution of the tool
---@return nil
function Executor:close()
  log:debug("Executor:close")
  self.handlers.on_exit()

  util.fire("AgentFinished", {
    name = self.tool.name,
    bufnr = self.agent.bufnr,
  })

  self.agent.chat.subscribers:process(self.agent.chat)
  vim.g.codecompanion_current_tool = nil
end

return Executor
