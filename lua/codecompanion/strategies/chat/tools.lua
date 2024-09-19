local Job = require("plenary.job")
local config = require("codecompanion").config

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

  USER_ROLE = "user",
  LLM_ROLE = "llm",
  SYSTEM_ROLE = "system",
}

local stderr = {}
local stdout = {}
local status = ""

---Parse XML in a given message
---@param message string
---@return table
local function parse_xml(message)
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  parser:parse(message)

  log:trace("Parsed xml: %s", handler.root)

  return handler.root.tool
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
---@field aug number
---@field bufnr number
---@field chat table
---@field messages table
---@field tool CodeCompanion.Tool the tool that's being run
---@field tools table
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
    tools = config.strategies.agent.tools,
    tools_ns = api.nvim_create_namespace(CONSTANTS.NS_TOOLS),
  }, { __index = Tools })

  return self
end

---Set the autocmds for the tool
---@return nil
function Tools:set_autocmds()
  return api.nvim_create_autocmd("User", {
    desc = "Handle responses from any agents",
    group = self.aug,
    pattern = "CodeCompanionAgent*",
    callback = function(request)
      if request.data.bufnr ~= self.bufnr then
        return
      end

      log:trace("Tool finished event: %s", request)

      if request.match == "CodeCompanionAgentStarted" then
        return ui.set_virtual_text(
          self.bufnr,
          self.tools_ns,
          "Tool processing ...",
          { hl_group = "CodeCompanionVirtualText" }
        )
      end

      api.nvim_buf_clear_namespace(self.bufnr, self.tools_ns, 0, -1)

      if self.tool.output_error_prompt and request.data.status == CONSTANTS.STATUS_ERROR then
        self.chat:append_to_buf({
          role = CONSTANTS.USER_ROLE,
          content = self.tool.output_error_prompt(request.data.error),
        })
        if self.tools.opts.auto_submit_errors then
          self.chat:submit()
        end
      end

      if self.tool.output_prompt and request.data.status == CONSTANTS.STATUS_SUCCESS then
        local output
        -- Sometimes, the output from a command will get sent to stderr instead
        -- of stdout. We can do a check and redirect the output accordingly
        if #request.data.output > 0 then
          output = request.data.output
        else
          output = request.data.error
        end

        local message = {
          role = CONSTANTS.USER_ROLE,
          content = self.tool.output_prompt(output),
        }

        if self.tools[self.tool.name].opts and self.tools[self.tool.name].opts.hide_output then
          self.chat:add_message(message, { visible = false })
          self.chat:append_to_buf({
            role = CONSTANTS.USER_ROLE,
            content = "I've shared the output with you",
          })
        else
          self.chat:append_to_buf(message)
          self.chat:fold_heading("tool output")
        end

        if self.tools.opts.auto_submit_success then
          self.chat:submit()
        end
      end

      self:reset()
    end,
  })
end

---Setup the tool in the chat buffer based on the LLM's response
---@param chat CodeCompanion.Chat
---@param xml string The XML schema from the LLM's response
---@return nil
function Tools:setup(chat, xml)
  self.chat = chat

  -- Parse the XML schema
  local ok, schema = pcall(function()
    return parse_xml(xml)
  end)
  if not ok then
    self.chat:add_message({
      role = CONSTANTS.USER_ROLE,
      content = string.format(
        "I'm sorry, your XML schema couldn't be processed. This is the error message:\n\n%s",
        schema
      ),
    }, { visible = false })
    self.chat:append_to_buf({
      role = CONSTANTS.USER_ROLE,
      content = "I've shared the error message with you",
    })
    if self.tools.opts.auto_submit_errors then
      self.chat:submit()
    end

    self:reset()
    return log:error("Error parsing XML schema: %s", schema)
  end

  -- Load the tool

  ---@type CodeCompanion.Tool|nil
  local tool = Tools.resolve(self.tools[schema.name])
  if not tool then
    return
  end

  self.tool = vim.deepcopy(tool)
  self.tool.request = schema
  self:fold_xml()
  self:set_autocmds()

  if self.tool.env then
    local env = type(self.tool.env) == "function" and self.tool.env(schema) or {}
    if self.tool.pre_cmd and type(self.tool.pre_cmd) == "function" then
      self.tool.pre_cmd(env, schema)
    end

    util.replace_placeholders(self.tool.cmds, env)
  end

  return self:run()
end

---Look for tools in a given message
---@param message table
---@return table|nil
function Tools:find(message)
  local found = {}
  for tool, _ in pairs(self.tools) do
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
      chat:add_tool(self.tools[tool])
    end
  end

  return chat
end

---Run the tool
---@return nil
function Tools:run()
  status = "success"
  stderr = {}
  stdout = {}
  _G.codecompanion_cancel_tool = false

  local function run(cmds, index, ...)
    if index > #cmds then
      return
    end

    local cmd = cmds[index]
    log:debug("Running cmd: %s", cmd)

    if type(cmd) == "function" then
      local ok, output = pcall(cmd, self, ...)
      if not ok then
        log:error("Error running command: %s", output)
        return util.fire("AgentFinished", { bufnr = self.bufnr, status = CONSTANTS.STATUS_ERROR, error = output })
      end

      if index == #cmds then
        ---Handle the case where the tool doesn't return anything
        if not output then
          output = { status = CONSTANTS.STATUS_SUCCESS, output = nil }
        end

        local event_data = { bufnr = self.bufnr, status = output.status, output = output.output }
        if output.status == CONSTANTS.STATUS_ERROR then
          event_data.error = output.output
          output = nil
        end
        return util.fire("AgentFinished", event_data)
      end

      return run(cmds, index + 1, output)
    else
      self.chat.current_tool = Job:new({
        command = cmd[1],
        args = { unpack(cmd, 2) }, -- args start from index 2
        on_exit = function(data, exit_code)
          self.chat.current_tool = nil
          run(cmds, index + 1, data)

          vim.schedule(function()
            if _G.codecompanion_cancel_tool then
              return util.fire(
                "AgentFinished",
                { bufnr = self.bufnr, status = status, error = stderr, output = stdout }
              )
            end

            if index == #cmds then
              if exit_code ~= 0 then
                status = "error"
                log:error("Command failed: %s", stderr)
              end
              return util.fire(
                "AgentFinished",
                { bufnr = self.bufnr, status = status, error = stderr, output = stdout }
              )
            end
          end)
        end,
        on_stdout = function(_, data)
          vim.schedule(function()
            log:trace("stdout: %s", data)
            if index == #cmds then
              table.insert(stdout, data)
            end
          end)
        end,
        on_stderr = function(_, data)
          table.insert(stderr, data)
        end,
      }):start()
    end
  end

  util.fire("AgentStarted", { bufnr = self.bufnr })
  return run(self.tool.cmds, 1)
end

---Replace the tool tag in a given message
---@param message string
---@return string
function Tools:replace(message)
  for tool, _ in pairs(self.tools) do
    message = vim.trim(message:gsub(CONSTANTS.PREFIX .. tool, ""))
  end
  return message
end

---Reset the tool class
---@return nil
function Tools:reset()
  api.nvim_clear_autocmds({ group = self.aug })
  api.nvim_buf_clear_namespace(self.bufnr, self.tools_ns, 0, -1)
  self.tool = {}

  -- Clear the chat to prevent infinite loops
  self.chat = {}
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

---Resolve a tool from the config
---@param tool table The tool from the config
---@return CodeCompanion.Tool|nil
function Tools.resolve(tool)
  local callback = tool.callback

  local ok, module = pcall(require, "codecompanion." .. callback)
  if not ok then
    --Try loading the tool from the user's config
    ok, module = pcall(require, callback)
  end
  if not ok then
    return log:error("Could not resolve tool: %s", callback)
  end

  log:trace("Calling tool: %s", callback)
  return module
end

return Tools
