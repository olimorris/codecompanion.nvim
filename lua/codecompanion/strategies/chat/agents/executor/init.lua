local CmdExecutor = require("codecompanion.strategies.chat.agents.executor.cmd")
local FuncExecutor = require("codecompanion.strategies.chat.agents.executor.func")
local Queue = require("codecompanion.strategies.chat.agents.executor.queue")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format

---Add a response to the chat buffer regarding a tool's execution
---@param exec CodeCompanion.Agent.Executor
---@msg string
local send_response_to_chat = function(exec, msg)
  exec.agent.chat:add_tool_output(exec.tool, msg)
end

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
      _G.codecompanion_current_tool = self.tool.name
      if self.tool.handlers and self.tool.handlers.setup then
        return self.tool.handlers.setup(self.tool, self.agent)
      end
    end,
    prompt_condition = function()
      if self.tool.handlers and self.tool.handlers.prompt_condition then
        return self.tool.handlers.prompt_condition(self.tool, self.agent, self.agent.tools_config)
      end
      return true
    end,
    on_exit = function()
      if self.tool.handlers and self.tool.handlers.on_exit then
        return self.tool.handlers.on_exit(self.tool, self.agent)
      end
    end,
  }

  self.output = {
    prompt = function()
      if self.tool.output and self.tool.output.prompt then
        return self.tool.output.prompt(self.tool, self.agent)
      end
    end,
    rejected = function(cmd)
      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(self.tool, self.agent, cmd)
      else
        -- If no handler is set then return a default message
        send_response_to_chat(self, fmt("User rejected `%s`", self.tool.name))
      end
    end,
    error = function(cmd)
      if self.tool.output and self.tool.output.error then
        self.tool.output.error(self.tool, self.agent, cmd, self.agent.stderr, self.agent.stdout or {})
      else
        send_response_to_chat(self, fmt("Error calling `%s`", self.tool.name))
      end
    end,
    cancelled = function(cmd)
      if self.tool.output and self.tool.output.cancelled then
        self.tool.output.cancelled(self.tool, self.agent, cmd)
      else
        send_response_to_chat(self, fmt("Cancelled `%s`", self.tool.name))
      end
    end,
    success = function(cmd)
      if self.tool.output and self.tool.output.success then
        self.tool.output.success(self.tool, self.agent, cmd, self.agent.stdout)
      else
        send_response_to_chat(self, fmt("Executed `%s`", self.tool.name))
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
    log:debug("Executor:execute - Queue empty")
    return finalize_agent(self)
  end
  if self.agent.status == self.agent.constants.STATUS_ERROR then
    log:debug("Executor:execute - Error")
    self:close()
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
  if self.tool.opts and not vim.g.codecompanion_auto_tool_mode then
    local requires_approval = self.tool.opts.requires_approval

    -- Users can set this to be a function if necessary
    if requires_approval and type(requires_approval) == "function" then
      requires_approval = requires_approval(self.tool, self.agent)
    end

    -- Anything that isn't a boolean will get evaluated with a prompt condition
    if requires_approval and type(requires_approval) ~= "boolean" then
      requires_approval = self.handlers.prompt_condition()
    end

    if requires_approval then
      log:debug("Executor:execute - Asking for approval")

      local prompt = self.output.prompt()
      if prompt == nil or prompt == "" then
        prompt = ("Run the %q tool?"):format(self.tool.name)
      end

      vim.ui.select({ "Yes", "No", "Cancel" }, {
        kind = "codecompanion.nvim",
        prompt = prompt,
        format_item = function(item)
          if item == "Yes" then
            return "Yes"
          elseif item == "No" then
            return "No"
          else
            return "Cancel"
          end
        end,
      }, function(choice)
        if not choice or choice == "Cancel" then -- No selection or cancelled
          log:debug("Executor:execute - Tool cancelled")
          self:close()
          self.output.cancelled(cmd)
          return self:setup()
        elseif choice == "Yes" then -- Selected yes
          log:debug("Executor:execute - Tool approved")
          self:execute(cmd, input)
        elseif choice == "No" then -- Selected no
          log:debug("Executor:execute - Tool rejected")
          self.output.rejected(cmd)
          self:setup()
        end
      end)
    else
      return self:execute(cmd, input)
    end
  else
    return self:execute(cmd, input)
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
---@param error? any
---@return nil
function Executor:error(action, error)
  log:debug("Executor:error")
  self.agent.status = self.agent.constants.STATUS_ERROR
  if type(error) == "string" then
    table.insert(self.agent.stderr, error)
    log:warn("Tool %s: %s", self.tool.name, error)
  end
  self.output.error(action)
  self:setup()
end

---Handle a successful completion of a tool
---@param action table
---@param output? any
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
  --TODO: This is a workaround that avoids the close method being called more than once
  if self.tool then
    log:debug("Executor:close")
    self.handlers.on_exit()
    util.fire("ToolFinished", { id = self.id, name = self.tool.name, bufnr = self.agent.bufnr })
    self.tool = nil
    self.current_cmd_tool = {}
  end
end

return Executor
