---@class CodeCompanion.Tools
---@field tools_config table The available tools for the tool system
---@field aug number The augroup for the tool
---@field bufnr number The buffer of the chat buffer
---@field constants table<string, string> The constants for the tool
---@field chat CodeCompanion.Chat The chat buffer that initiated the tool
---@field extracted table The extracted tools from the LLM's response
---@field messages table The messages in the chat buffer
---@field status string The status of the tool
---@field stdout table The stdout of the tool
---@field stderr table The stderr of the tool
---@field tool CodeCompanion.Tools.Tool The current tool that's being run
---@field tools_ns integer The namespace for the virtual text that appears in the header

local EditTracker = require("codecompanion.strategies.chat.edit_tracker")
local Orchestrator = require("codecompanion.strategies.chat.tools.orchestrator")
local ToolFilter = require("codecompanion.strategies.chat.tools.tool_filter")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local regex = require("codecompanion.utils.regex")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")

local api = vim.api

local show_tools_processing = config.display.chat.show_tools_processing

local CONSTANTS = {
  PREFIX = "@",

  NS_TOOLS = "CodeCompanion-tools",
  AUTOCMD_GROUP = "codecompanion.tools",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  PROCESSING_MSG = config.display.icons.loading .. " Tools processing ...",
}

---@class CodeCompanion.Tools
local Tools = {}

---@param args table
function Tools.new(args)
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
    tools_config = ToolFilter.filter_enabled_tools(config.strategies.chat.tools), -- Filter here
    tools_ns = api.nvim_create_namespace(CONSTANTS.NS_TOOLS),
  }, { __index = Tools })

  return self
end

---Refresh the tools configuration to pick up any dynamically added tools
---@return CodeCompanion.Tools
function Tools:refresh()
  self.tools_config = ToolFilter.filter_enabled_tools(config.strategies.chat.tools)
  return self
end

---Set the autocmds for the tool
---@return nil
function Tools:set_autocmds()
  api.nvim_create_autocmd("User", {
    desc = "Handle responses from the Tool system",
    group = self.aug,
    pattern = "CodeCompanionTools*",
    callback = function(request)
      if request.data.bufnr ~= self.bufnr then
        return
      end

      if request.match == "CodeCompanionToolsStarted" then
        log:info("[Tool System] Initiated")
        if show_tools_processing then
          local namespace = CONSTANTS.NS_TOOLS .. "_" .. tostring(self.bufnr)
          ui.show_buffer_notification(self.bufnr, {
            namespace = namespace,
            text = CONSTANTS.PROCESSING_MSG,
            main_hl = "CodeCompanionChatInfo",
            spacer = true,
          })
        end
      elseif request.match == "CodeCompanionToolsFinished" then
        return vim.schedule(function()
          local auto_submit = function()
            return self.chat:submit({
              auto_submit = true,
              callback = function()
                self:reset({ auto_submit = true })
              end,
            })
          end

          if vim.g.codecompanion_auto_tool_mode then
            return auto_submit()
          end
          if self.status == CONSTANTS.STATUS_ERROR and self.tools_config.opts.auto_submit_errors then
            return auto_submit()
          end
          if self.status == CONSTANTS.STATUS_SUCCESS and self.tools_config.opts.auto_submit_success then
            return auto_submit()
          end

          self:reset({ auto_submit = false })
        end)
      end
    end,
  })
end

---Parse and normalize tool arguments
---@param tool table The tool with function and arguments
---@return table|nil args The parsed arguments or nil if parsing failed
---@return string|nil error_msg Error message if parsing failed
function Tools:_parse_tool_arguments(tool)
  local args = tool["function"].arguments
  if not args then
    return nil, nil
  end

  if type(args) == "string" then
    local success, decoded = pcall(vim.json.decode, args)
    if success then
      return decoded, nil
    else
      return nil, string.format("Couldn't decode the tool arguments: %s", args)
    end
  end

  return args, nil
end

---Handle missing or invalid tool errors
---@param tool table The tool that failed
---@param error_message string The error message
---@return nil
function Tools:_handle_tool_error(tool, error_message)
  local name = tool["function"].name
  local tool_call = vim.deepcopy(tool)
  tool_call.name = name
  tool_call.function_call = tool_call

  log:error(error_message)
  
  local available_tools_msg = next(self.chat.tool_registry.in_use or {})
      and "The available tools are: " .. table.concat(
        vim.tbl_map(function(t)
          return "`" .. t .. "`"
        end, vim.tbl_keys(self.chat.tool_registry.in_use)),
        ", "
      )
    or "No tools available"
  
  self.chat:add_tool_output(tool_call, string.format("Tool `%s` not found. %s", name, available_tools_msg), "")
  return util.fire("ToolsFinished", { bufnr = self.bufnr })
end

---Resolve and prepare a tool for execution
---@param tool table The tool call from the LLM
---@return table|nil resolved_tool The resolved tool or nil if failed
---@return string|nil error_msg Error message if resolution failed
function Tools:_resolve_and_prepare_tool(tool)
  local name = tool["function"].name
  local tool_config = self.tools_config[name]
  
  if not tool_config then
    return nil, string.format("Couldn't find the tool `%s`", name)
  end

  local ok, resolved_tool = pcall(function()
    return Tools.resolve(tool_config)
  end)
  
  if not ok or not resolved_tool then
    return nil, string.format("Couldn't resolve the tool `%s`", name)
  end

  local prepared_tool = vim.deepcopy(resolved_tool)
  prepared_tool.name = name
  prepared_tool.function_call = tool

  -- Parse and set arguments
  local args, parse_error = self:_parse_tool_arguments(tool)
  if parse_error then
    return nil, parse_error
  end
  prepared_tool.args = args

  -- Merge options
  prepared_tool.opts = vim.tbl_extend("force", prepared_tool.opts or {}, tool_config.opts or {})

  -- Handle environment variables
  if prepared_tool.env then
    local env = type(prepared_tool.env) == "function" and prepared_tool.env(vim.deepcopy(prepared_tool)) or {}
    util.replace_placeholders(prepared_tool.cmds, env)
  end

  return prepared_tool, nil
end

---Start edit tracking for all tools
---@param tools table The tools to track
---@return nil
function Tools:_start_edit_tracking(tools)
  for _, tool in ipairs(tools) do
    local tool_name = tool["function"].name
    local tool_args, _ = self:_parse_tool_arguments(tool)
    EditTracker.start_tool_monitoring(tool_name, self.chat, tool_args)
  end
end

---Execute the tool in the chat buffer based on the LLM's response
---@param chat CodeCompanion.Chat
---@param tools table The tools requested by the LLM
---@return nil
function Tools:execute(chat, tools)
  local id = math.random(10000000)
  self.chat = chat

  -- Start edit tracking for all tools
  self:_start_edit_tracking(tools)

  -- Wrap the entire tool execution in error handling
  local function safe_execute()
    local orchestrator = Orchestrator.new(self, id)
    
    -- Process each tool
    for _, tool in ipairs(tools) do
      local resolved_tool, error_msg = self:_resolve_and_prepare_tool(tool)
      
      if not resolved_tool then
        return self:_handle_tool_error(tool, error_msg)
      end
      
      self.tool = resolved_tool
      orchestrator.queue:push(self.tool)
    end

    self:set_autocmds()
    util.fire("ToolsStarted", { id = id, bufnr = self.bufnr })
    orchestrator:setup()
  end

  -- Execute all tools with error handling
  local ok, err = xpcall(safe_execute, function(error_msg)
    return debug.traceback(error_msg, 2)
  end)

  if not ok then
    log:error("chat::tools::init::execute - Execution error %s", err)
    self.status = CONSTANTS.STATUS_ERROR
    vim.schedule(function()
      util.fire("ToolsFinished", { id = id, bufnr = self.bufnr })
    end)
  end
end

---Creates a regex pattern to match a tool name in a message
---@param tool string The tool name to create a pattern for
---@return string The compiled regex pattern
function Tools:_pattern(tool)
  return CONSTANTS.PREFIX .. "{" .. tool .. "}"
end

---Look for tools in a given message
---@param chat CodeCompanion.Chat
---@param message table
---@return table?, table?
function Tools:find(chat, message)
  if not message.content then
    return nil, nil
  end

  local groups = {}
  local tools = {}

  ---@param tool string The tool name to search for
  ---@return number?,number? The start position of the match, or nil if not found
  local function is_found(tool)
    local pattern = self:_pattern(tool)
    return regex.find(message.content, pattern)
  end

  -- Process groups
  vim.iter(self.tools_config.groups):each(function(tool)
    if is_found(tool) then
      table.insert(groups, tool)
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

  if #tools == 0 and #groups == 0 then
    return nil, nil
  end

  return tools, groups
end

---Parse a user message looking for a tool
---@param chat CodeCompanion.Chat
---@param message table
---@return boolean
function Tools:parse(chat, message)
  local tools, groups = self:find(chat, message)

  if tools or groups then
    if tools and not vim.tbl_isempty(tools) then
      for _, tool in ipairs(tools) do
        chat.tool_registry:add(tool, self.tools_config[tool])
      end
    end

    if groups and not vim.tbl_isempty(groups) then
      for _, group in ipairs(groups) do
        chat.tool_registry:add_group(group, self.tools_config)
      end
    end
    return true
  end

  return false
end

---Replace the tool tag in a given message
---@param message string
---@return string
function Tools:replace(message)
  for tool, _ in pairs(self.tools_config) do
    if tool ~= "opts" and tool ~= "groups" then
      message = vim.trim(regex.replace(message, self:_pattern(tool), tool))
    end
  end
  for group, _ in pairs(self.tools_config.groups) do
    local tools = table.concat(self.tools_config.groups[group].tools, ", ")
    message = vim.trim(regex.replace(message, self:_pattern(group), tools))
  end
  return message
end

---Reset the Tools class
---@param opts? table
---@return nil
function Tools:reset(opts)
  opts = opts or {}

  if show_tools_processing then
    ui.clear_notification(self.bufnr, { namespace = CONSTANTS.NS_TOOLS .. "_" .. tostring(self.bufnr) })
  end

  api.nvim_clear_autocmds({ group = self.aug })

  self.extracted = {}
  self.status = CONSTANTS.STATUS_SUCCESS
  self.stderr = {}
  self.stdout = {}

  self.chat:tools_done(opts)
  log:info("[Tools] Completed")
end

---Add an error message to the chat buffer
---@param error string
---@return CodeCompanion.Tools
function Tools:add_error_to_chat(error)
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
---@return CodeCompanion.Tools.Tool|nil
function Tools.resolve(tool)
  local callback = tool.callback

  if type(callback) == "table" then
    return callback --[[@as CodeCompanion.Tools.Tool]]
  end

  if type(callback) == "function" then
    return callback() --[[@as CodeCompanion.Tools.Tool]]
  end

  local ok, module = pcall(require, "codecompanion." .. callback)
  if ok then
    log:debug("[Tools] %s identified", callback)
    return module
  end

  -- Try loading the tool from the user's config using a module path
  ok, module = pcall(require, callback)
  if ok then
    log:debug("[Tools] %s identified", callback)
    return module
  end

  -- Try loading the tool from the user's config using a file path
  local err
  module, err = loadfile(callback)
  if err then
    return error()
  end

  if module then
    log:debug("[Tools] %s identified", callback)
    return module()
  end
end

return Tools
