---@class CodeCompanion.Agent
---@field tools_config table The agent strategy from the config
---@field aug number The augroup for the tool
---@field bufnr number The buffer of the chat buffer
---@field constants table<string, string> The constants for the tool
---@field chat CodeCompanion.Chat The chat buffer that initiated the tool
---@field extracted table The extracted tools from the LLM's response
---@field messages table The messages in the chat buffer
---@field status string The status of the tool
---@field stdout table The stdout of the tool
---@field stderr table The stderr of the tool
---@field tool CodeCompanion.Agent.Tool The current tool that's being run
---@field tools_ns integer The namespace for the virtual text that appears in the header

local Executor = require("codecompanion.strategies.chat.agents.executor")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")

local api = vim.api

local CONSTANTS = {
  PREFIX = "@",

  NS_TOOLS = "CodeCompanion-agents",
  AUTOCMD_GROUP = "codecompanion.agent",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  PROCESSING_MSG = "Tool processing ...",
}

---@class CodeCompanion.Agent
local Agent = {}

---@param args table
function Agent.new(args)
  local self = setmetatable({
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. args.bufnr, { clear = true }),
    bufnr = args.bufnr,
    chat = {},
    constants = CONSTANTS,
    extracted = {},
    messages = args.messages,
    stdout = {},
    stderr = {},
    tool = {},
    tools_config = config.strategies.chat.tools,
    tools_ns = api.nvim_create_namespace(CONSTANTS.NS_TOOLS),
  }, { __index = Agent })

  return self
end

---Set the autocmds for the tool
---@return nil
function Agent:set_autocmds()
  api.nvim_create_autocmd("User", {
    desc = "Handle responses from an Agent",
    group = self.aug,
    pattern = "CodeCompanionAgent*",
    callback = function(request)
      if request.data.bufnr ~= self.bufnr then
        return
      end

      if request.match == "CodeCompanionAgentStarted" then
        log:info("[Agent] Initiated")
        return ui.set_virtual_text(
          self.bufnr,
          self.tools_ns,
          CONSTANTS.PROCESSING_MSG,
          { hl_group = "CodeCompanionVirtualText" }
        )
      elseif request.match == "CodeCompanionAgentFinished" then
        return vim.schedule(function()
          self:reset()
          if self.status == CONSTANTS.STATUS_ERROR and self.tools_config.opts.auto_submit_errors then
            self.chat:submit()
          end
          if self.status == CONSTANTS.STATUS_SUCCESS and self.tools_config.opts.auto_submit_success then
            self.chat:submit()
          end
        end)
      end
    end,
  })
end

---Execute the tool in the chat buffer based on the LLM's response
---@param chat CodeCompanion.Chat
---@param tools table The tools requested by the LLM
---@return nil
function Agent:execute(chat, tools)
  self.chat = chat

  ---Resolve and run the tool
  ---@param executor CodeCompanion.Agent.Executor The executor instance
  ---@param tool table The tool to run
  local function enqueue_tool(executor, tool)
    -- If an error occurred, don't run any more tools
    if self.status == CONSTANTS.STATUS_ERROR then
      return
    end

    local name = tool["function"].name
    local tool_config = self.tools_config[name]
    local function handle_missing_tool(tool_call, err_message)
      tool_call.name = name
      tool_call.function_call = tool_call
      log:error(err_message)
      local available_tools_msg = next(chat.tools.in_use or {})
          and "The available tools are: " .. table.concat(
            vim.tbl_map(function(t)
              return "`" .. t .. "`"
            end, vim.tbl_keys(chat.tools.in_use)),
            ", "
          )
        or "No tools available"
      self.chat:add_tool_output(
        tool_call,
        string.format("Tool `%s` not found. %s", name, available_tools_msg),
        string.format("**%s Tool Error**: %s", name, err_message)
      )
      return util.fire("AgentFinished", { bufnr = self.bufnr })
    end
    if not tool_config then
      return handle_missing_tool(vim.deepcopy(tool), string.format("Couldn't find the tool `%s`", name))
    end

    local ok, resolved_tool = pcall(function()
      return Agent.resolve(tool_config)
    end)
    if not ok or not resolved_tool then
      return handle_missing_tool(vim.deepcopy(tool), string.format("Couldn't resolve the tool `%s`", name))
    end

    self.tool = vim.deepcopy(resolved_tool)

    self.tool.name = name
    self.tool.function_call = tool
    if tool["function"].arguments then
      local args = tool["function"].arguments
      -- For some adapter's that aren't streaming, the args are strings rather than tables
      if type(args) == "string" then
        local decoded
        xpcall(function()
          decoded = vim.json.decode(args)
        end, function(err)
          log:error("Couldn't decode the tool arguments: %s", args)
          self.chat:add_tool_output(
            self.tool,
            string.format('You made an error in calling the %s tool: "%s"', name, err),
            string.format("**%s Tool Error**: %s", util.capitalize(name), err)
          )
          return util.fire("AgentFinished", { bufnr = self.bufnr })
        end)
        args = decoded
      end
      self.tool.args = args
    end
    self.tool.opts = vim.tbl_extend("force", self.tool.opts or {}, tool_config.opts or {})

    if self.tool.env then
      local env = type(self.tool.env) == "function" and self.tool.env(vim.deepcopy(self.tool)) or {}
      util.replace_placeholders(self.tool.cmds, env)
    end

    return executor.queue:push(self.tool)
  end

  local id = math.random(10000000)
  local executor = Executor.new(self, id)

  for _, tool in ipairs(tools) do
    enqueue_tool(executor, tool)
  end
  self:set_autocmds()

  util.fire("AgentStarted", { id = id, bufnr = self.bufnr })
  xpcall(function()
    executor:setup()
  end, function(err)
    log:error("Agent execution error:\n%s", err)
    util.fire("AgentFinished", { id = id, bufnr = self.bufnr })
  end)
end

---Look for tools in a given message
---@param chat CodeCompanion.Chat
---@param message table
---@return table?, table?
function Agent:find(chat, message)
  if not message.content then
    return nil, nil
  end

  local groups = {}
  local tools = {}

  local function is_found(tool)
    return message.content:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. tool .. "%f[%W]")
  end

  -- Process groups
  vim.iter(self.tools_config.groups):each(function(tool)
    if is_found(tool) then
      table.insert(groups, tool)

      for _, t in ipairs(self.tools_config.groups[tool].tools) do
        if not vim.tbl_contains(tools, t) then
          table.insert(tools, t)
        end
      end
    end
  end)

  -- Process tools
  vim
    .iter(self.tools_config)
    :filter(function(name)
      return name ~= "opts" and name ~= "groups"
    end)
    :each(function(tool)
      if is_found(tool) and not vim.tbl_contains(tools, tool) then
        table.insert(tools, tool)
      end
    end)

  if #tools == 0 then
    return nil, nil
  end

  return tools, groups
end

---Parse a user message looking for a tool
---@param chat CodeCompanion.Chat
---@param message table
---@return boolean
function Agent:parse(chat, message)
  local tools, groups = self:find(chat, message)

  if tools or groups then
    if tools and not vim.tbl_isempty(tools) then
      for _, tool in ipairs(tools) do
        chat.tools:add(tool, self.tools_config[tool])
      end
    end

    if groups and not vim.tbl_isempty(groups) then
      for _, group in ipairs(groups) do
        local schema = self.tools_config.groups[group]
        local system_prompt = schema.system_prompt
        if type(system_prompt) == "function" then
          system_prompt = system_prompt(schema)
        end
        if system_prompt then
          chat:add_message({
            role = config.constants.SYSTEM_ROLE,
            content = system_prompt,
          }, { tag = "tool", visible = false })
        end
      end
    end
    return true
  end

  return false
end

---Replace the tool tag in a given message
---@param message string
---@return string
function Agent:replace(message)
  for tool, _ in pairs(self.tools_config) do
    if tool ~= "opts" and tool ~= "groups" then
      message = vim.trim(message:gsub(CONSTANTS.PREFIX .. tool, tool))
    end
  end
  for group, _ in pairs(self.tools_config.groups) do
    local tools = table.concat(self.tools_config.groups[group].tools, ", ")
    message = vim.trim(message:gsub(CONSTANTS.PREFIX .. group, tools))
  end

  return message
end

---Reset the Agent class
---@return nil
function Agent:reset()
  api.nvim_buf_clear_namespace(self.bufnr, self.tools_ns, 0, -1)
  api.nvim_clear_autocmds({ group = self.aug })

  self.extracted = {}
  self.status = CONSTANTS.STATUS_SUCCESS
  self.stderr = {}
  self.stdout = {}

  self.chat:tools_done()
  log:info("[Agent] Completed")
end

---Add an error message to the chat buffer
---@param error string
---@return CodeCompanion.Agent
function Agent:add_error_to_chat(error)
  self.chat:add_message({
    role = config.constants.USER_ROLE,
    content = error,
  }, { visible = false })

  --- Alert the user that the error message has been shared
  self.chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = "Please correct for the error message I've shared",
  })

  if self.tools_config.opts and self.tools_config.opts.auto_submit_errors then
    self.chat:submit()
  end

  return self
end

---Resolve a tool from the config
---@param tool table The tool from the config
---@return CodeCompanion.Agent.Tool|nil
function Agent.resolve(tool)
  local callback = tool.callback

  if type(callback) == "table" then
    return callback --[[@as CodeCompanion.Agent.Tool]]
  end

  if type(callback) == "function" then
    return callback() --[[@as CodeCompanion.Agent.Tool]]
  end

  local ok, module = pcall(require, "codecompanion." .. callback)
  if ok then
    log:debug("[Tools] %s identified", callback)
    return module
  end

  -- Try loading the tool from the user's config
  ok, module = pcall(loadfile, callback)
  if not ok then
    return error()
  end

  if module then
    log:debug("[Tools] %s identified", callback)
    return module()
  end
end

return Agent
