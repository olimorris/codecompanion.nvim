local Queue = require("codecompanion.strategies.chat.tools.runtime.queue")
local Runner = require("codecompanion.strategies.chat.tools.runtime.runner")
local log = require("codecompanion.utils.log")
local tool_utils = require("codecompanion.utils.tools")
local utils = require("codecompanion.utils")

local fmt = string.format

---Add a response to the chat buffer regarding a tool's execution
---@param exec CodeCompanion.Tools.Orchestrator
---@msg string
local send_response_to_chat = function(exec, msg)
  exec.tools.chat:add_tool_output(exec.tool, msg)
end

---Converts a cmd-based tool to a function-based tool.
---@param tool CodeCompanion.Tools.Tool
---@return CodeCompanion.Tools.Tool
local function cmd_to_func_tool(tool)
  --NOTE: The `env` field should be processed in the tool beforehand

  tool.cmds = vim
    .iter(tool.cmds)
    :map(function(cmd)
      if type(cmd) == "function" then
        -- function-based tool
        return cmd
      else
        local flag = cmd.flag
        cmd = cmd.cmd or cmd
        if type(cmd) == "string" then
          cmd = vim.split(cmd, " ", { trimempty = true })
        end

        ---@param tools CodeCompanion.Tools
        return function(tools, _, _, cb)
          cb = vim.schedule_wrap(cb)
          vim.system(tool_utils.build_shell_command(cmd), {}, function(out)
            -- Flags can be read higher up in the tool's execution
            if flag then
              tools.chat.tool_registry.flags = tools.chat.tool_registry.flags or {}
              tools.chat.tool_registry.flags[flag] = (out.code == 0)
            end
            if out.code == 0 then
              cb({
                status = "success",
                data = tool_utils.strip_ansi(vim.split(out.stdout, "\n", { trimempty = true })),
              })
            else
              local stderr = {}
              if out.stderr and out.stderr ~= "" then
                stderr = tool_utils.strip_ansi(vim.split(out.stderr, "\n", { trimempty = true }))
              end

              -- Some commands may return an error but populate stdout
              local stdout = {}
              if out.stdout and out.stdout ~= "" then
                stdout = tool_utils.strip_ansi(vim.split(out.stdout, "\n", { trimempty = true }))
              end

              local combined = {}
              vim.list_extend(combined, stderr)
              vim.list_extend(combined, stdout)

              cb({
                status = "error",
                data = combined,
              })
            end
          end)
        end
      end
    end)
    :totable()

  return tool
end

---@class CodeCompanion.Tools.Orchestrator
---@field tools CodeCompanion.Tools
---@field handlers table<string, function>
---@field id number The id of the tools coordinator
---@field index number The index of the current command
---@field output table<string, function>
---@field tool CodeCompanion.Tools.Tool
---@field queue CodeCompanion.Tools.Orchestrator.Queue
---@field status string
local Orchestrator = {}

---@param tools CodeCompanion.Tools
---@param id number
function Orchestrator.new(tools, id)
  local self = setmetatable({
    tools = tools,
    id = id,
    queue = Queue.new(),
  }, { __index = Orchestrator })

  _G.codecompanion_cancel_tool = false

  return self
end

---Add the tool's handlers to the executor
---@return nil
function Orchestrator:setup_handlers()
  self.handlers = {
    setup = function()
      if not self.tool then
        return
      end
      _G.codecompanion_current_tool = self.tool.name
      if self.tool.handlers and self.tool.handlers.setup then
        return self.tool.handlers.setup(self.tool, self.tools)
      end
    end,
    prompt_condition = function()
      if not self.tool then
        return
      end

      if self.tool.handlers and self.tool.handlers.prompt_condition then
        return self.tool.handlers.prompt_condition(self.tool, self.tools, self.tools.tools_config)
      end
      return true
    end,
    on_exit = function()
      if not self.tool then
        return
      end

      if self.tool.handlers and self.tool.handlers.on_exit then
        return self.tool.handlers.on_exit(self.tool, self.tools)
      end
    end,
  }

  self.output = {
    prompt = function()
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.prompt then
        return self.tool.output.prompt(self.tool, self.tools)
      end
    end,
    rejected = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(self.tool, self.tools, cmd)
      else
        -- If no handler is set then return a default message
        send_response_to_chat(self, fmt("User rejected `%s`", self.tool.name))
      end
    end,
    error = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.error then
        self.tool.output.error(self.tool, self.tools, cmd, self.tools.stderr)
      else
        send_response_to_chat(self, fmt("Error calling `%s`", self.tool.name))
      end
    end,
    cancelled = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.cancelled then
        self.tool.output.cancelled(self.tool, self.tools, cmd)
      else
        send_response_to_chat(self, fmt("Cancelled `%s`", self.tool.name))
      end
    end,
    success = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.success then
        self.tool.output.success(self.tool, self.tools, cmd, self.tools.stdout)
      else
        send_response_to_chat(self, fmt("Executed `%s`", self.tool.name))
      end
    end,
  }
end

---When the tools coordinator is finished, finalize it via an autocmd
---@param self CodeCompanion.Tools.Orchestrator
---@return nil
local function finalize_tools(self)
  return utils.fire("ToolsFinished", { id = self.id, bufnr = self.tools.bufnr })
end

---Setup the tool to be executed
---@param input? any
---@return nil
function Orchestrator:setup(input)
  if self.queue:is_empty() then
    log:debug("Orchestrator:execute - Queue empty")
    return finalize_tools(self)
  end
  if self.tools.status == self.tools.constants.STATUS_ERROR then
    log:debug("Orchestrator:execute - Error")
    self:close()
  end

  -- Get the next tool to run
  self.tool = self.queue:pop()

  -- Setup the handlers
  self:setup_handlers()
  self.handlers.setup() -- Call this early as cmd_runner needs to setup its cmds dynamically

  self.tool = cmd_to_func_tool(self.tool) -- transform cmd-based tools to func-based

  -- Get the first command to run
  local cmd = self.tool.cmds[1]
  log:debug("Orchestrator:execute - `%s` tool", self.tool.name)

  -- Check if the tool requires approval
  if self.tool.opts and not vim.g.codecompanion_auto_tool_mode then
    local requires_approval = self.tool.opts.requires_approval

    -- Users can set this to be a function if necessary
    if requires_approval and type(requires_approval) == "function" then
      requires_approval = requires_approval(self.tool, self.tools)
    end

    -- Anything that isn't a boolean will get evaluated with a prompt condition
    if requires_approval and type(requires_approval) ~= "boolean" then
      requires_approval = self.handlers.prompt_condition()
    end

    if requires_approval then
      log:debug("Orchestrator:execute - Asking for approval")

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
          log:debug("Orchestrator:execute - Tool cancelled")
          self:close()
          self.output.cancelled(cmd)
          return self:setup()
        elseif choice == "Yes" then -- Selected yes
          log:debug("Orchestrator:execute - Tool approved")
          self:execute(cmd, input)
        elseif choice == "No" then -- Selected no
          log:debug("Orchestrator:execute - Tool rejected")
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
---@param cmd function
---@param input? any
---@return nil
function Orchestrator:execute(cmd, input)
  utils.fire("ToolStarted", { id = self.id, tool = self.tool.name, bufnr = self.tools.bufnr })
  return Runner.new(self, cmd, 1):setup(input)
end

---Handle an error from a tool
---@param action table
---@param error? any
---@return nil
function Orchestrator:error(action, error)
  log:debug("Orchestrator:error")
  self.tools.status = self.tools.constants.STATUS_ERROR
  table.insert(self.tools.stderr, error)

  local ok, err = pcall(function()
    self.output.error(action)
  end)
  if not ok then
    log:error("Internal error with the %s error handler: %s", self.tool.name, err)
    if self.tool and self.tool.function_call then
      self.tools.chat:add_tool_output(self.tool, string.format("Internal error with `%s` tool", self.tool.name))
    end
  end

  self:setup()
end

---Handle a successful completion of a tool
---@param action table
---@param output? any
---@return nil
function Orchestrator:success(action, output)
  log:debug("Orchestrator:success")
  self.tools.status = self.tools.constants.STATUS_SUCCESS
  if output then
    table.insert(self.tools.stdout, output)
  end
  local ok, err = pcall(function()
    self.output.success(action)
  end)

  if not ok then
    log:error("Internal error with the %s success handler: %s", self.tool.name, err)
    if self.tool and self.tool.function_call then
      self.tools.chat:add_tool_output(self.tool, string.format("Internal error with `%s` tool", self.tool.name))
    end
  end
end

---Close the execution of the tool
---@return nil
function Orchestrator:close()
  if self.tool then
    log:debug("Orchestrator:close")
    pcall(function()
      self.handlers.on_exit()
    end)
    utils.fire("ToolFinished", { id = self.id, name = self.tool.name, bufnr = self.tools.bufnr })
    self.tool = nil
  end
end

return Orchestrator
