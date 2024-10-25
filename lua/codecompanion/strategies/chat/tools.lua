local Job = require("plenary.job")
local config = require("codecompanion.config")

local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
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
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  -- parser.options.stripWS = nil
  parser:parse(message)

  log:trace("Parsed xml: %s", handler.root)

  return handler.root.tools
end

---@class CodeCompanion.Tool
---@field name string The name of the tool
---@field cmds table The commands to execute
---@field schema table The schema that the LLM must use in its response to execute a tool
---@field system_prompt fun(schema: table): string The system prompt to the LLM explaining the tool and the schema
---@field opts? table The options for the tool
---@field env? fun(schema: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field pre_cmd? fun(env: table, schema: table): table|nil Function to call before the cmd table is executed
---@field output_error_prompt? fun(error: table|string): string The prompt to share with the LLM if an error is encountered
---@field output_prompt? fun(output: table): string The prompt to share with the LLM if the cmd is successful
---@field request table The request from the LLM to use the Tool

---@class CodeCompanion.Tools
---@field aug number The augroup for the tool
---@field bufnr number The buffer of the chat buffer
---@field chat CodeCompanion.Chat The chat buffer that initiated the tool
---@field messages table The messages in the chat buffer
---@field tool CodeCompanion.Tool The current tool that's being run
---@field tools_config table The Tools from the config
---@field tools_ns integer The namespace for the virtual text that appears in the header
local Tools = {}

---@param args table
function Tools.new(args)
  local self = setmetatable({
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. args.bufnr, { clear = true }),
    bufnr = args.bufnr,
    chat = {},
    messages = args.messages,
    tool = {},
    tools_config = config.strategies.agent.tools,
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
        log:debug("Agent started")
        return ui.set_virtual_text(
          self.bufnr,
          self.tools_ns,
          CONSTANTS.PROCESSING_MSG,
          { hl_group = "CodeCompanionVirtualText" }
        )
      elseif request.match == "CodeCompanionAgentFinished" then
        api.nvim_buf_clear_namespace(self.bufnr, self.tools_ns, 0, -1)

        -- Handle any errors
        if request.data.status == CONSTANTS.STATUS_ERROR and self.tool.output_error_prompt then
          log:debug("Tool %s finished with error", self.tool.name)
          self.chat:append_to_buf({
            role = config.constants.USER_ROLE,
            content = self.tool.output_error_prompt(request.data.stderr),
          })
          if self.tools_config.opts.auto_submit_errors then
            self.chat:submit()
          end
        end

        -- Handle any success
        if request.data.status == CONSTANTS.STATUS_SUCCESS and self.tool.output_prompt then
          local output = request.data.stdout

          log:debug("Tool output: %s", output)

          local message = {
            role = config.constants.USER_ROLE,
            content = self.tool.output_prompt(output),
          }

          if self.tools_config[self.tool.name].opts and self.tools_config[self.tool.name].opts.hide_output then
            self.chat:add_message(message, { visible = false })
            self.chat:append_to_buf({
              role = config.constants.USER_ROLE,
              content = "I've shared the output with you",
            })
          else
            self.chat:append_to_buf(message)
            self.chat:fold_heading("tool output")
          end

          if self.tools_config.opts.auto_submit_success then
            self.chat:submit()
          end
        end
        self:reset()
      end
    end,
  })
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
  local resolved_tool = Tools.resolve(self.tools_config[schema.tool._attr.name])
  if not resolved_tool then
    return
  end

  self.tool = vim.deepcopy(resolved_tool)
  self.tool.request = schema.tool
  self:fold_xml()
  self:set_autocmds()

  if self.tool.env then
    local env = type(self.tool.env) == "function" and self.tool.env(schema.tool) or {}
    if self.tool.pre_cmd and type(self.tool.pre_cmd) == "function" then
      self.tool.pre_cmd(env, schema.tool)
    end

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

  ---Action to take when closing the job
  local function close()
    vim.schedule(function()
      util.fire(
        "AgentFinished",
        { name = self.tool.name, bufnr = self.bufnr, status = status, stderr = stderr, stdout = stdout }
      )
    end)
  end

  ---Run the commands in the tool
  ---@param cmds table
  ---@param index number
  ---@param ... any
  local function run(cmds, index, ...)
    if index > #cmds or status == CONSTANTS.STATUS_ERROR then
      return close()
    end

    local cmd = cmds[index]
    log:debug("Running cmd: %s", cmd)

    if type(cmd) == "function" then
      local ok, output = pcall(cmd, self, ...)
      if not ok then
        stderr = output
        status = CONSTANTS.STATUS_ERROR
        log:error("Error calling function in %s: %s", self.tool.name, stderr)
        return close()
      end

      if index == #cmds then
        if output.status == CONSTANTS.STATUS_ERROR then
          status = CONSTANTS.STATUS_ERROR
          log:error("Error whilst running %s: %s", self.tool.name, stderr)
        else
          stdout = output.output
        end
      end

      run(cmds, index + 1, output)
    else
      self.chat.current_tool = Job:new({
        command = cmd[1],
        args = { unpack(cmd, 2) }, -- args start from index 2
        on_exit = function(data, _)
          self.chat.current_tool = nil

          vim.schedule(function()
            if _G.codecompanion_cancel_tool then
              stderr = stderr
              stdout = stdout
              return close()
            end
            run(cmds, index + 1, data)
          end)
        end,
        on_stdout = function(_, data)
          vim.schedule(function()
            if index == #cmds then
              table.insert(stdout, data)
            end
          end)
        end,
        on_stderr = function(err, _)
          if err then
            vim.schedule(function()
              stderr = err
              status = CONSTANTS.STATUS_ERROR
              log:error("Error running tool %s: %s", self.tool.name, err)
              return close()
            end)
          end
        end,
      }):start()
    end
  end

  util.fire("AgentStarted", { tool = self.tool.name, bufnr = self.bufnr })
  return run(self.tool.cmds, 1)
end

---Look for tools in a given message
---@param message table
---@return table|nil
function Tools:find(message)
  if not message.content then
    return nil
  end

  local found = {}
  for tool, _ in pairs(self.tools_config) do
    if message.content:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. tool .. "%f[%W]") then
      table.insert(found, tool)
    end
  end

  if #found == 0 then
    return nil
  end

  return found
end

---@param chat CodeCompanion.Chat
---@param message table
function Tools:parse(chat, message)
  local tools = self:find(message)
  if tools then
    for _, tool in ipairs(tools) do
      chat:add_tool(self.tools_config[tool])
    end
  end

  return chat
end

---Replace the tool tag in a given message
---@param message string
---@return string
function Tools:replace(message)
  for tool, _ in pairs(self.tools_config) do
    message = vim.trim(message:gsub(CONSTANTS.PREFIX .. tool, ""))
  end
  return message
end

---Reset the tool class
---@return nil
function Tools:reset()
  api.nvim_clear_autocmds({ group = self.aug })

  self.tool = {}
  self.chat = {}

  log:debug("Agent finished")
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

  for _, matches, _ in query:iter_matches(tree:root(), self.bufnr, 0, -1, { all = false }) do
    local code_node = matches[2] -- The second capture is always the code block
    if code_node then
      local start_row, _, end_row, _ = code_node:range()
      if start_row < end_row then
        api.nvim_buf_call(self.chat.bufnr, function()
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
  self.chat:append_to_buf({
    role = config.constants.USER_ROLE,
    content = "Please correct for the error message I've shared",
  })

  if self.tools_config.opts.auto_submit_errors then
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
    log:debug("Calling tool: %s", callback)
    return module
  end

  -- Try loading the tool from the user's config
  ok, module = pcall(loadfile, callback)
  if not ok then
    return log:error("Could not resolve tool: %s", callback)
  end

  if module then
    log:debug("Calling tool: %s", callback)
    return module()
  end
end

return Tools
