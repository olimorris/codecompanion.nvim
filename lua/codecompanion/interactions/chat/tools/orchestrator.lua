local Queue = require("codecompanion.interactions.chat.tools.runtime.queue")
local Runner = require("codecompanion.interactions.chat.tools.runtime.runner")
local log = require("codecompanion.utils.log")
local os_utils = require("codecompanion.utils.os")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local fmt = string.format

---Strip any ANSI color codes which don't render in the chat buffer
---@param tbl table
---@return table
local function strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

---Add a response to the chat buffer regarding a tool's execution
---@param exec CodeCompanion.Tools.Orchestrator
---@param llm_message string
---@param user_message? string
local send_response_to_chat = function(exec, llm_message, user_message)
  exec.tools.chat:add_tool_output(exec.tool, llm_message, user_message)
end

---Execute a shell command with platform-specific handling
---@param cmd table
---@param callback function
local function execute_shell_command(cmd, callback)
  if vim.fn.has("win32") == 1 then
    -- See PR #2186
    local shell_cmd = table.concat(cmd, " ") .. "\r\nEXIT %ERRORLEVEL%\r\n"
    vim.system({ "cmd.exe", "/Q", "/K" }, {
      stdin = shell_cmd,
      env = { PROMPT = "\r\n" },
    }, callback)
  else
    vim.system(os_utils.build_shell_command(cmd), {}, callback)
  end
end

---Converts a cmd-based tool to a function-based tool.
---@param tool CodeCompanion.Tools.Tool
---@return CodeCompanion.Tools.Tool
local function cmd_to_func_tool(tool)
  tool.cmds = vim
    .iter(tool.cmds)
    :map(function(cmd)
      if type(cmd) == "function" then
        return cmd
      end

      local flag = cmd.flag
      cmd = cmd.cmd or cmd
      if type(cmd) == "string" then
        cmd = vim.split(cmd, " ", { trimempty = true })
      end

      ---@param tools CodeCompanion.Tools
      return function(tools, _, _, cb)
        cb = vim.schedule_wrap(cb)
        execute_shell_command(cmd, function(out)
          if flag then
            tools.chat.tool_registry.flags = tools.chat.tool_registry.flags or {}
            tools.chat.tool_registry.flags[flag] = (out.code == 0)
          end

          local eol_pattern = vim.fn.has("win32") == 1 and "\r?\n" or "\n"

          if out.code == 0 then
            cb({
              status = "success",
              data = strip_ansi(vim.split(out.stdout, eol_pattern, { trimempty = true })),
            })
          else
            local combined = {}
            if out.stderr and out.stderr ~= "" then
              vim.list_extend(combined, strip_ansi(vim.split(out.stderr, eol_pattern, { trimempty = true })))
            end
            if out.stdout and out.stdout ~= "" then
              vim.list_extend(combined, strip_ansi(vim.split(out.stdout, eol_pattern, { trimempty = true })))
            end
            cb({ status = "error", data = combined })
          end
        end)
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
    rejected = function(cmd, opts)
      if not self.tool then
        return
      end

      opts = opts or {}

      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(self.tool, self.tools, cmd, opts)
      else
        local rejection = fmt("\nThe user rejected the execution of the %s tool", self.tool.name)
        if opts.reason then
          rejection = rejection .. fmt(': "%s"', opts.reason)
        end
        -- If no handler is set then return a default message
        send_response_to_chat(self, rejection)
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
        send_response_to_chat(
          self,
          fmt("The user cancelled the execution of the %s tool", self.tool.name),
          fmt("Cancelled `%s`", self.tool.name)
        )
      end
    end,
    success = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.success then
        self.tool.output.success(self.tool, self.tools, cmd, self.current_tool_stdout or {})
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
    return finalize_tools(self)
  end

  -- Get the next tool to run
  self.tool = self.queue:pop()
  self.current_tool_stdout = {}

  -- Setup the handlers
  self:setup_handlers()
  self.handlers.setup() -- Call this early as cmd_runner needs to setup its cmds dynamically

  self.tool = cmd_to_func_tool(self.tool) -- transform cmd-based tools to func-based

  -- Get the first command to run
  local cmd = self.tool.cmds[1]
  log:debug("Orchestrator:execute - `%s` tool", self.tool.name)

  -- Check if the tool requires approval
  if self.tool.opts and not vim.g.codecompanion_yolo_mode then
    local require_approval_before = self.tool.opts.require_approval_before

    -- Users can set this to be a function if necessary
    if require_approval_before and type(require_approval_before) == "function" then
      require_approval_before = require_approval_before(self.tool, self.tools)
    end

    -- Anything that isn't a boolean will get evaluated with a prompt condition
    if require_approval_before and type(require_approval_before) ~= "boolean" then
      require_approval_before = self.handlers.prompt_condition()
    end

    if require_approval_before then
      log:debug("Orchestrator:execute - Asking for approval")

      local prompt = self.output.prompt()
      if prompt == nil or prompt == "" then
        prompt = ("Run the %q tool?"):format(self.tool.name)
      end

      -- Schedule the confirmation dialog to ensure UI is ready
      vim.schedule(function()
        local choice = ui_utils.confirm(prompt, { "1 Allow always", "2 Allow once", "3 Reject", "4 Cancel" })
        log:debug("Orchestrator:execute - User choice: %s", choice)

        -- Handle invalid/failed dialog (returns 0 or nil)
        if not choice or choice == 0 then
          log:warn("Orchestrator:execute - Confirm dialog failed, rejecting tool and continuing")
          self.output.rejected(cmd, { reason = "Confirmation dialog failed" })
          self:close()
          return self:setup()
        end

        if choice == 1 or choice == 2 then
          log:debug("Orchestrator:execute - Tool approved")
          if choice == 1 then
            vim.g.codecompanion_yolo_mode = true
          end
          return self:execute(cmd, input)
        elseif choice == 3 then
          log:debug("Orchestrator:execute - Tool rejected")
          ui_utils.input({ prompt = fmt("Reason for rejecting `%s`", self.tool.name) }, function(i)
            self.output.rejected(cmd, { reason = i })
            return self:setup()
          end)
        else
          log:debug("Orchestrator:execute - Tool cancelled")
          -- NOTE: Cancel current tool, then cancel all queued tools
          self.output.cancelled(cmd)
          self:close()
          self:cancel_pending_tools()
          return self:setup()
        end
      end)
    else
      return self:execute(cmd, input)
    end
  else
    log:debug("Orchestrator:execute - No tool approval required")
    return self:execute(cmd, input)
  end
end

---Cancel all pending tools in the queue
---@return nil
function Orchestrator:cancel_pending_tools()
  while not self.queue:is_empty() do
    local pending_tool = self.queue:pop()
    self.tool = pending_tool

    -- Prepare handlers/output first
    self:setup_handlers()
    local first_cmd = pending_tool.cmds and pending_tool.cmds[1] or nil

    local ok, err = pcall(function()
      self.output.cancelled(first_cmd)
    end)
    if not ok then
      log:error("Failed to run cancelled handler for tool %s: %s", tostring(pending_tool.name), err)
    end
  end
end

---Execute the tool command
---@param cmd function
---@param input? any
---@return nil
function Orchestrator:execute(cmd, input)
  utils.fire("ToolStarted", { id = self.id, tool = self.tool.name, bufnr = self.tools.bufnr })

  pcall(function()
    local edit_tracker = require("codecompanion.interactions.chat.edit_tracker")
    self.execution_id = edit_tracker.start_tool_monitoring(self.tool.name, self.tools.chat, self.tool.args)
  end)

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

  if self.tool and self.tool.name then
    -- Wrap this in error handling to avoid breaking the tool execution
    pcall(function()
      local edit_tracker = require("codecompanion.interactions.chat.edit_tracker")
      edit_tracker.finish_tool_monitoring(self.tool.name, self.tools.chat, false, self.execution_id)
    end)
  end

  local ok, err = pcall(function()
    self.output.error(action)
  end)
  if not ok then
    log:error("Internal error with the %s error handler: %s", self.tool.name, err)
    if self.tool and self.tool.function_call then
      self.tools.chat:add_tool_output(self.tool, string.format("Internal error with `%s` tool", self.tool.name))
    end
  end

  self:close()
  self:setup()
end

---Handle a successful completion of a tool
---@param action table
---@param output? any
---@return nil
function Orchestrator:success(action, output)
  log:debug("Orchestrator:success")
  self.tools.status = self.tools.constants.STATUS_SUCCESS

  if self.tool and self.tool.name then
    pcall(function()
      local edit_tracker = require("codecompanion.interactions.chat.edit_tracker")
      edit_tracker.finish_tool_monitoring(self.tool.name, self.tools.chat, true, self.execution_id)
    end)
  end

  if output then
    table.insert(self.tools.stdout, output)
    if not self.current_tool_stdout then
      self.current_tool_stdout = {}
    end
    table.insert(self.current_tool_stdout, output)
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
