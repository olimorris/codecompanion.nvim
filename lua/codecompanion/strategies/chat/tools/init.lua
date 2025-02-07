local Job = require("plenary.job")
local config = require("codecompanion.config")

local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
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

---Some commands output ANSI color codes so we need to strip them
---@param tbl table
---@return table
local function strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

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

---@class CodeCompanion.Tools
local Tools = {}

---@param args table
function Tools.new(args)
  local self = setmetatable({
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. args.bufnr, { clear = true }),
    bufnr = args.bufnr,
    chat = {},
    extracted = {},
    messages = args.messages,
    tool = {},
    agent_config = config.strategies.chat.agents,
    tools_ns = api.nvim_create_namespace(CONSTANTS.NS_TOOLS),
  }, { __index = Tools })

  return self
end

---Set the autocmds for the tool
---@return nil
function Tools:set_autocmds()
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
function Tools:parse_buffer(chat, start_range, end_range)
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
      return self:setup(chat, t)
    end)
  end
end

---Setup the tool in the chat buffer based on the LLM's response
---@param chat CodeCompanion.Chat
---@param xml string The XML schema from the LLM's response
---@return nil
function Tools:setup(chat, xml)
  self.chat = chat

  local ok, schema = pcall(parse_xml, xml)
  if not ok then
    self:add_error_to_chat(string.format("The XML schema couldn't be processed:\n\n%s", schema)):reset()
    return log:error("Error parsing XML schema: %s", schema)
  end

  ---@type CodeCompanion.Tool|nil
  local resolved_tool = Tools.resolve(self.agent_config.tools[schema.tool._attr.name])
  if not resolved_tool then
    return
  end

  self.tool = vim.deepcopy(resolved_tool)
  self.tool.request = schema.tool
  self:fold_xml()
  self:set_autocmds()

  if self.tool.env then
    local env = type(self.tool.env) == "function" and self.tool.env(schema.tool) or {}
    util.replace_placeholders(self.tool.cmds, env)
  end

  self:run()
end

---Run the tool
---@return nil
function Tools:run()
  local stderr = {}
  local stdout = {}
  local status = CONSTANTS.STATUS_SUCCESS
  _G.codecompanion_cancel_tool = false

  local requires_approval = (
    config.strategies.chat.agents.tools[self.tool.name].opts
      and config.strategies.chat.agents.tools[self.tool.name].opts.user_approval
    or false
  )

  local handlers = {
    setup = function()
      vim.g.codecompanion_current_tool = self.tool.name
      if self.tool.handlers and self.tool.handlers.setup then
        self.tool.handlers.setup(self)
      end
    end,
    approved = function(cmd)
      if self.tool.handlers and self.tool.handlers.approved then
        return self.tool.handlers.approved(self, cmd)
      end
      return true
    end,
    on_exit = function()
      if self.tool.handlers and self.tool.handlers.on_exit then
        self.tool.handlers.on_exit(self)
      end
    end,
  }

  local output = {
    rejected = function(cmd)
      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(self, cmd)
      end
    end,
    error = function(cmd, error)
      if self.tool.output and self.tool.output.error then
        self.tool.output.error(self, cmd, error)
      end
    end,
    success = function(cmd, output)
      if self.tool.output and self.tool.output.success then
        self.tool.output.success(self, cmd, output)
      end
    end,
  }

  ---Action to take when closing the job
  local function close()
    handlers.on_exit()

    util.fire(
      "AgentFinished",
      { name = self.tool.name, bufnr = self.bufnr, status = status, stderr = stderr, stdout = stdout }
    )

    status = CONSTANTS.STATUS_SUCCESS
    stderr = {}
    stdout = {}

    self.chat.subscribers:process(self.chat)
    vim.g.codecompanion_current_tool = nil
  end

  ---Run the commands in the tool
  ---@param index number
  ---@param ... any
  local function run(index, ...)
    local function continue()
      if not self.tool.cmds then
        return false
      end
      if index >= vim.tbl_count(self.tool.cmds) or status == CONSTANTS.STATUS_ERROR then
        return false
      end
      return true
    end

    local cmd = self.tool.cmds[index]
    log:debug("[Tools] Running cmd: %s", self.tool.name)

    ---Execute a function tool
    local function execute_func(action, ...)
      if requires_approval and not handlers.approved(action) then
        output.rejected(action)
        if not continue() then
          return close()
        end
      end

      local ok, data = pcall(function(...)
        return cmd(self, action, ...)
      end)
      if not ok then
        status = CONSTANTS.STATUS_ERROR
        table.insert(stderr, data)
        log:error("Error calling function in %s: %s", self.tool.name, data)
        output.error(action, data)
        return close()
      end

      if data.status == CONSTANTS.STATUS_ERROR then
        status = CONSTANTS.STATUS_ERROR
        table.insert(stderr, data.msg)
        output.error(action, data.msg)
      else
        table.insert(stdout, data.msg)
        output.success(action, data.msg)
      end

      if not continue() then
        return close()
      end

      run(index + 1, output)
    end

    -- Tools that are setup as Lua functions
    if type(cmd) == "function" then
      local action = self.tool.request.action
      if type(action) == "table" and type(action[1]) == "table" then
        for _, a in ipairs(action) do
          execute_func(a, ...)
        end
      else
        execute_func(action, ...)
      end
    end

    -- Tools that are setup as shell commands
    if type(cmd) == "table" then
      if requires_approval and not handlers.approved(cmd) then
        output.rejected(cmd)
        if not continue() then
          return close()
        end
      end

      -- Delay executing the job to allow for output to be collated and processed
      self.chat.current_tool = Job:new({
        command = vim.fn.has("win32") == 1 and "cmd.exe" or "sh",
        args = { vim.fn.has("win32") == 1 and "/c" or "-c", table.concat(cmd.cmd or cmd, " ") },
        enable_recording = true,
        cwd = vim.fn.getcwd(),
        on_stdout = function(_, data)
          vim.schedule(function()
            table.insert(strip_ansi(stdout), data)
          end)
        end,
        on_stderr = function(err, _)
          if err then
            vim.schedule(function()
              stderr = strip_ansi(err)
              status = CONSTANTS.STATUS_ERROR
              log:error("Error running tool %s: %s", self.tool.name, err)
              return close()
            end)
          end
        end,
        on_exit = function(data, code)
          self.chat.current_tool = nil

          -- Handle the LLM setting any flags
          if cmd.flag then
            self.chat.tool_flags = self.chat.tool_flags or {}
            self.chat.tool_flags[cmd.flag] = (code == 0)
          end

          log:debug("[Tools] %s finished with code %s", self.tool.name, code)

          vim.schedule(function()
            if _G.codecompanion_cancel_tool then
              stdout = strip_ansi(stdout)
              stderr = strip_ansi(stderr)
              return close()
            end

            if vim.tbl_isempty(stdout) and vim.tbl_isempty(stderr) then
              if code == 0 then
                output.success(cmd, "Tool finished successfully but with no output")
              else
                output.error(cmd, "Tool failed with code " .. code .. " and no output")
              end
            elseif not vim.tbl_isempty(stderr) then
              output.error(cmd, strip_ansi(stderr))
              log:debug("[Tools] %s finished with stderr: %s", self.tool.name, stderr)
              stderr = {}
            elseif not vim.tbl_isempty(stdout) then
              output.success(cmd, strip_ansi(stdout))
              log:trace("[Tools] %s finished with output: %s", self.tool.name, stdout)
              stdout = {}
            end

            if not continue() then
              return close()
            end

            run(index + 1, data)
          end)
        end,
      }):start()
    end
  end

  util.fire("AgentStarted", { tool = self.tool.name, bufnr = self.bufnr })

  handlers.setup()
  return run(1)
end

---Look for tools in a given message
---@param chat CodeCompanion.Chat
---@param message table
---@return table?, table?
function Tools:find(chat, message)
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
function Tools:parse(chat, message)
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
function Tools:replace(message)
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
function Tools:reset()
  api.nvim_buf_clear_namespace(self.bufnr, self.tools_ns, 0, -1)
  api.nvim_clear_autocmds({ group = self.aug })
  self.extracted = {}
  log:info("[Agent] Completed")
end

---Fold any XML code blocks in the buffer
---@return nil
function Tools:fold_xml()
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

  if self.agent_config.opts and self.agent_config.opts.auto_submit_errors then
    self.chat:submit()
  end

  return self
end

---Resolve a tool from the config
---@param tool table The tool from the config
---@return CodeCompanion.Tool|nil
function Tools.resolve(tool)
  local callback = tool.callback

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

return Tools
