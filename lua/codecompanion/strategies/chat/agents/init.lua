---@class CodeCompanion.Agent
---@field agent_config table The agent strategy from the config
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
local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local CONSTANTS = {
  PREFIX = "@",

  NS_TOOLS = "CodeCompanion-agents",
  AUTOCMD_GROUP = "codecompanion.agent",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  PROCESSING_MSG = "Tool processing ...",
}

---Parse XML in a given message
---@param message string
---@return table
local function parse_xml(message)
  log:trace("Trying to parse: %s", message)

  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  -- parser.options.stripWS = nil
  parser:parse(message)

  log:trace("Parsed xml: %s", handler.root)

  return handler.root.tools
end

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
    agent_config = config.strategies.chat.agents,
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
        -- Handle any errors
        if request.data.status == CONSTANTS.STATUS_ERROR then
          local error = request.data.stderr
          log:error("Tool %s finished with error(s): %s", string.upper(self.tool.name), error)

          if self.tool.output and self.tool.output.errors then
            self.tool.output.errors(self, error)
          end
          if self.agent_config.tools.opts.auto_submit_errors then
            self.chat:submit()
          end
        end

        -- Handle any success
        if request.data.status == CONSTANTS.STATUS_SUCCESS then
          if self.agent_config.tools.opts.auto_submit_success then
            self.chat:submit()
          end
        end
      end
      self:reset()
    end,
  })
end

---Parse a chat buffer for tools
---@param chat CodeCompanion.Chat
---@param start_range number
---@param end_range number
---@return nil
function Agent:parse_buffer(chat, start_range, end_range)
  local query = vim.treesitter.query.get("markdown", "tools")
  local tree = chat.parser:parse({ start_range - 1, end_range - 1 })[1]

  local llm = {}
  for id, node in query:iter_captures(tree:root(), chat.bufnr, start_range - 1, end_range - 1) do
    if query.captures[id] == "content" then
      table.insert(llm, vim.treesitter.get_node_text(node, chat.bufnr))
    end
  end

  if vim.tbl_isempty(llm) then
    return
  end

  -- NOTE: Only work with the last response from the LLM
  local response = llm[#llm]

  local parser = vim.treesitter.get_string_parser(response, "markdown")
  tree = parser:parse()[1]

  local tools = {}
  for id, node in query:iter_captures(tree:root(), response, 0, -1) do -- NOTE: Keep this scoped to 0,-1
    if query.captures[id] == "tool" then
      local tool = vim.treesitter.get_node_text(node, response)
      tool = tool:gsub("^`+", ""):gsub("```$", "")
      table.insert(tools, vim.trim(tool))
    end
  end

  log:trace("[Tools] Detected: %s", tools)

  if not vim.tbl_isempty(tools) then
    self.extracted = tools
    vim.iter(tools):each(function(t)
      return self:execute(chat, t)
    end)
  end
end

---Execute the tool in the chat buffer based on the LLM's response
---@param chat CodeCompanion.Chat
---@param xml string The XML schema from the LLM's response
---@return nil
function Agent:execute(chat, xml)
  self.chat = chat

  local ok, schema = pcall(parse_xml, xml)
  if not ok then
    self:add_error_to_chat(string.format("The XML schema couldn't be processed:\n\n%s", schema)):reset()
    return log:error("Error parsing XML schema: %s", schema)
  end

  ---Resolve and run the tool
  ---@param executor CodeCompanion.Agent.Executor The executor instance
  ---@param s table The tool's schema
  local function run_tool(executor, s)
    -- If an error occurred, don't run any more tools
    if self.status == CONSTANTS.STATUS_ERROR then
      return
    end

    local name = s.tool._attr.name
    local tool_config = self.agent_config.tools[name]

    ---@type CodeCompanion.Agent.Tool|nil
    local resolved_tool
    ok, resolved_tool = pcall(function()
      return Agent.resolve(tool_config)
    end)
    if not ok or not resolved_tool then
      log:error("Couldn't resolve the tool(s) from the LLM's response")
      log:info("XML:\n%s", xml)
      log:info("Schema:\n%s", s)
      return
    end

    self.tool = vim.deepcopy(resolved_tool)
    self.tool.name = name
    self.tool.opts = tool_config.opts and tool_config.opts or {}
    self.tool.request = s.tool
    self:fold_xml()
    self:set_autocmds()

    if self.tool.env then
      local env = type(self.tool.env) == "function" and self.tool.env(s.tool) or {}
      util.replace_placeholders(self.tool.cmds, env)
    end

    return executor.queue:push(self.tool)
  end

  local executor = Executor.new(self)

  -- This allows us to run multiple tools in a single response whether they're in
  -- their own XML block or they're in an array within the <tools> tag
  if vim.isarray(schema.tool) then
    vim.iter(schema.tool):each(function(tool)
      run_tool(executor, { tool = tool })
    end)
  else
    run_tool(executor, schema)
  end

  return executor:setup()
end

---Look for tools in a given message
---@param chat CodeCompanion.Chat
---@param message table
---@return table?, table?
function Agent:find(chat, message)
  if not message.content then
    return nil, nil
  end

  local agents = {}
  local tools = {}

  local function is_found(tool)
    return message.content:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. tool .. "%f[%W]")
  end

  -- Process agents
  vim
    .iter(self.agent_config)
    :filter(function(name)
      return name ~= "tools"
    end)
    :each(function(agent)
      if is_found(agent) then
        table.insert(agents, agent)

        for _, tool in ipairs(self.agent_config[agent].tools) do
          if not vim.tbl_contains(tools, tool) then
            table.insert(tools, tool)
          end
        end
      end
    end)

  -- Process tools
  vim
    .iter(self.agent_config.tools)
    :filter(function(name)
      return name ~= "opts"
    end)
    :each(function(tool)
      if is_found(tool) and not vim.tbl_contains(tools, tool) then
        table.insert(tools, tool)
      end
    end)

  if #tools == 0 then
    return nil, nil
  end

  return tools, agents
end

---@param chat CodeCompanion.Chat
---@param message table
---@return boolean
function Agent:parse(chat, message)
  local tools, agents = self:find(chat, message)

  if tools or agents then
    if tools and not vim.tbl_isempty(tools) then
      for _, tool in ipairs(tools) do
        chat:add_tool(tool, self.agent_config.tools[tool])
      end
    end

    if agents and not vim.tbl_isempty(agents) then
      for _, agent in ipairs(agents) do
        if self.agent_config[agent].system_prompt then
          chat:add_message({
            role = config.constants.SYSTEM_ROLE,
            content = self.agent_config[agent].system_prompt,
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
  for tool, _ in pairs(self.agent_config.tools) do
    message = vim.trim(message:gsub(CONSTANTS.PREFIX .. tool, tool))
  end
  for agent, _ in pairs(self.agent_config) do
    message = vim.trim(message:gsub(CONSTANTS.PREFIX .. agent, ""))
  end

  return message
end

---Reset the tool class
---@return nil
function Agent:reset()
  api.nvim_buf_clear_namespace(self.bufnr, self.tools_ns, 0, -1)
  api.nvim_clear_autocmds({ group = self.aug })

  self.extracted = {}
  self.status = CONSTANTS.STATUS_SUCCESS
  self.stderr = {}
  self.stdout = {}

  log:info("[Agent] Completed")
end

---Fold any XML code blocks in the buffer
---@return nil
function Agent:fold_xml()
  local query = vim.treesitter.query.parse(
    "markdown",
    [[
(
 fenced_code_block
 (info_string) @lang
 (code_fence_content) @code
 (#eq? @lang "xml")
)
  ]]
  )

  local parser = vim.treesitter.get_parser(self.bufnr, "markdown")
  local tree = parser:parse()[1]

  vim.o.foldmethod = "manual"

  for _, matches, _ in query:iter_matches(tree:root(), self.bufnr) do
    local nodes = matches[2] -- The second capture is always the code block
    local code_node = type(nodes) == "table" and nodes[1] or nodes

    if code_node then
      local start_row, _, end_row, _ = code_node:range()
      if start_row < end_row then
        api.nvim_buf_call(self.bufnr, function()
          vim.cmd(string.format("%d,%dfold", start_row, end_row))
        end)
      end
    end
  end
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

  if self.agent_config.opts and self.agent_config.opts.auto_submit_errors then
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

  local ok, module = pcall(require, "codecompanion." .. callback)
  if ok then
    log:debug("[Tools] %s identified", callback)
    return module
  end

  -- Try loading the tool from the user's config
  ok, module = pcall(loadfile, callback)
  if not ok then
    return log:error("[Tools] %s could not be resolved", callback)
  end

  if module then
    log:debug("[Tools] %s identified", callback)
    return module()
  end
end

return Agent
