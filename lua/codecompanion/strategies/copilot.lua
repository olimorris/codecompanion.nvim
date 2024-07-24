local client = require("codecompanion.client")
local config = require("codecompanion").config
local log = require("codecompanion.utils.log")
local n = require("nui-components")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api

local Chat = require("codecompanion.strategies.chat")
local ToolManager = require("codecompanion.tools.tool_manager")

local CONSTANTS = {
  AU_USER_EVENT = "CodeCompanionChat",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",
  STATUS_FINISHED = "finished",
}

local chat_query = [[
(
  atx_heading
  (atx_h1_marker)
  heading_content: (_) @role
)
(
  section
  [(paragraph) (section) (fenced_code_block) (list)] @text
)
]]

local _cached_settings = {}

---@param adapter? CodeCompanion.Adapter|string|function
---@return CodeCompanion.Adapter
local function resolve_adapter(adapter)
  adapter = adapter or config.adapters[config.strategies.copilot.adapter]

  if type(adapter) == "string" then
    return require("codecompanion.adapters").use(adapter)
  elseif type(adapter) == "function" then
    return adapter()
  end

  return adapter
end

---@param bufnr integer
---@param adapter? CodeCompanion.Adapter
---@param ts_query? string
---@return table
local function parse_settings(bufnr, adapter, ts_query)
  if _cached_settings[bufnr] then
    return _cached_settings[bufnr]
  end

  -- If the user has disabled settings in the chat buffer, use the default settings
  if not config.display.chat.show_settings then
    if adapter then
      _cached_settings[bufnr] = adapter:get_default_settings()

      return _cached_settings[bufnr]
    end
  end

  ts_query = ts_query or [[
    ((block_mapping (_)) @block)
  ]]

  local settings = {}
  local parser = vim.treesitter.get_parser(bufnr, "yaml", { ignore_injections = false })
  local query = vim.treesitter.query.parse("yaml", ts_query)
  local root = parser:parse()[1]:root()

  for _, match in query:iter_matches(root, bufnr) do
    local value = vim.treesitter.get_node_text(match[1], bufnr)

    settings = yaml.decode(value)
    break
  end

  if not settings then
    log:error("Failed to parse settings in chat buffer")
    return {}
  end

  return settings
end

---@param bufnr integer
---@return table
local function parse_messages(bufnr)
  local output = {}

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local query = vim.treesitter.query.parse("markdown", chat_query)
  local root = parser:parse()[1]:root()

  local captures = {}
  for k, v in pairs(query.captures) do
    captures[v] = k
  end

  local message = {}
  for _, match in query:iter_matches(root, bufnr) do
    if match[captures.role] then
      if not vim.tbl_isempty(message) then
        table.insert(output, message)
        message = { role = "", content = "" }
      end
      message.role = vim.trim(vim.treesitter.get_node_text(match[captures.role], bufnr):lower())
    elseif match[captures.text] then
      local text = vim.trim(vim.treesitter.get_node_text(match[captures.text], bufnr))
      if message.content then
        message.content = message.content .. "\n\n" .. text
      else
        message.content = text
      end
      if not message.role then
        message.role = "user"
      end
    end
  end

  if not vim.tbl_isempty(message) then
    table.insert(output, message)
  end

  return output
end

---parse the tool call from the response
---@param content string
---@return string|nil, string|nil
local function parse_tool_call(content)
  local tool_name, args = content:match("%(([^%)]+)%)%s*\n```\n(.-)\n```")
  -- local tool_name, args = content:match("%(([^%)]+)%)%s*\n%-%-%-\n(.-)\n%-%-%-")
  log:info("parse_tool_call: %s, %s", tool_name, args)
  if not tool_name or not args then
    return nil, nil
  end
  return tool_name, args:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
end

---@class CodeCompanion.CopilotArgs : CodeCompanion.ChatArgs
---@field tools? CodeCompanion.CopilotTool[]

---@class CodeCompanion.Copilot : CodeCompanion.Chat
---@field current_tool? CodeCompanion.CopilotTool current running tool
---@field tool_manager? CodeCompanion.ToolManager tool manager
---@field current_assistant_response string current assistant response
local Copilot = setmetatable({}, { __index = Chat })
Copilot.__index = Copilot

---@param args CodeCompanion.CopilotArgs
function Copilot.new(args)
  local auto_submit = args.auto_submit
  local saved_chat = args.saved_chat

  args.auto_submit = false
  args.saved_chat = ""

  -- resolve adapter before new chat
  -- make sure the settings are set and rendered
  args.adapter = resolve_adapter(args.adapter)

  -- set stop sequences
  if args.adapter.args.schema.stop then
    log:info("set stop sequences")
    --- openai api stop
    args.adapter.args.schema.stop.default = {
      "output:==",
    }
  elseif args.adapter.args.schema.stop_sequences then
    log:info("set stop sequences")
    --- anthropic api stop
    args.adapter.args.schema.stop_sequences.default = {
      "output:==",
    }
  end

  local self = setmetatable(Chat.new(args), Copilot)

  args.auto_submit = auto_submit
  args.saved_chat = saved_chat

  self.current_assistant_response = ""
  self.tool_manager = ToolManager.new()

  -- register tools
  if args.tools then
    for _, t in ipairs(args.tools) do
      ---@type CodeCompanion.CopilotTool
      local tool = t.new(self)
      self.tool_manager:register_tool(tool.name, tool.new(self))
    end
  end

  if args.saved_chat then
    self:display_tokens()
  end

  if args.auto_submit then
    self:submit()
  end

  return self
end

---Submit the chat buffer's contents to the LLM
---@return nil
function Copilot:submit()
  local bufnr = self.bufnr
  local settings, messages = parse_settings(bufnr, self.adapter), parse_messages(bufnr)
  if not messages or #messages == 0 or (not messages[#messages].content or messages[#messages].content == "") then
    return
  end

  if config.strategies.copilot.system_prompt then
    table.insert(messages, 1, {
      role = "system",
      content = config.strategies.copilot.system_prompt(self),
    })
  end

  -- Detect if the user has called any variables in their latest message
  local vars = self.variables:parse(self, messages[#messages].content, #messages)
  if vars then
    -- For the message that includes the variable, remove it from the content
    -- so we don't confuse the LLM. We don't need to remove the variable in
    -- future replies as the LLM has already processed it.
    messages[#messages].content = self.variables:replace(messages[#messages].content, vars)
    table.insert(self.variable_output, vars)
  end

  -- Always add the variables to the same place in the message stack
  if self.variable_output then
    for i, var in ipairs(self.variable_output) do
      table.insert(messages, var.index, {
        role = "user",
        content = var.content,
      })

      if i == 1 then
        -- Insert workspace_prompt before the variable content
        table.insert(messages, var.index, {
          role = "user",
          content = config.strategies.copilot.workspace_prompt(self),
        })
      end
    end

    -- remove all history variable output
    self.variable_output = {}
  end

  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  self.current_assistant_response = ""

  self.current_request = client.new():stream(self.adapter:set_params(settings), messages, function(err, data, done)
    if err then
      vim.notify("Error: " .. err, vim.log.levels.ERROR)
      return self:reset()
    end

    -- With some adapters, the tokens come as part of the regular response so
    -- we need to account for that here before the client is terminated
    if data then
      self:get_tokens(data)
    end

    if done then
      local content = self.current_assistant_response
      log:info("current_assistant_response: %s", content)
      self.current_assistant_response = ""

      local tool_name, args = parse_tool_call(content)

      if tool_name then
        return self:execute_tool(tool_name, args)
      else
        self:append({ role = "user", content = "#buffers \n\n" })

        self:display_tokens()
        api.nvim_exec_autocmds(
          "User",
          { pattern = CONSTANTS.AU_USER_EVENT, data = { status = CONSTANTS.STATUS_FINISHED } }
        )
        return self:reset()
      end
    end

    if data and data ~= "data: [DONE]" then
      local result = self.adapter.args.callbacks.chat_output(data)
      if result and result.status == CONSTANTS.STATUS_SUCCESS then
        self.current_assistant_response = self.current_assistant_response .. (result.output.content or "")
        self:append(result.output)
      elseif result and result.status == CONSTANTS.STATUS_ERROR then
        self.status = CONSTANTS.STATUS_ERROR
        self:stop()
        vim.notify("Error: " .. result.output, vim.log.levels.ERROR)
      end
    end
  end, function()
    self.current_request = nil
  end)
end

---execute tool
---@param tool_name string
---@param args string|nil
function Copilot:execute_tool(tool_name, args)
  local tool = self.tool_manager:get_tool(tool_name)

  if not tool then
    log:error("Tool '%s' not found", tool_name)
    return self:reset()
  end

  require("codecompanion.tools.autocmd").set_autocmd(self, tool)
  tool:run(args)
end

---When a request has finished, reset the chat buffer
---@return nil
function Copilot:reset()
  --- call parent reset
  self.current_tool = nil
  Chat.reset(self)
end

function Copilot:get_tool_descriptions()
  return self.tool_manager:get_tool_descriptions()
end

function Copilot:get_tool_examples()
  return self.tool_manager:get_tool_examples()
end

return Copilot
