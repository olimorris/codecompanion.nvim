local config = require("codecompanion").config
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local M = {}

---@class CodeCompanion.Tool
---@field cmd table The commands to execute
---@field schema table The schema that the LLM must use in its response to execute a tool
---@field opts? table The options for the tool
---@field system_prompt fun(schema: table): string The system prompt to the LLM explaining the tool and the schema
---@field env fun(xml: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field pre_cmd fun(env: table, xml: table): table|nil Function to call before the cmd table is executed
---@field override_cmds fun(cmds: table): table Function to call to override the default cmds table
---@field output_error_prompt fun(error: table): string The prompt to share with the LLM if an error is encountered
---@field output_prompt fun(output: table): string The prompt to share with the LLM if the cmd is successful
---@field execute fun(chat: CodeCompanion.Chat, inputs: table): CodeCompanion.ToolExecuteResult|nil Function to execute the tool (used by Buffer Editor)

---@class CodeCompanion.ToolExecuteResult
---@field success boolean Whether the tool was successful
---@field message string The message to display to the user
---@field modified_files? table<string, string> The files that were modified by the tool

---@class CodeCompanion.ToolExecuteInputs

---Parse the Tree-sitter output into XML
---@param agents table
---@return table
local function parse_xml(agents)
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  parser:parse(agents)

  log:trace("Parsed xml: %s", handler.root)

  return handler.root.tool
end

---Set the autocmds for the tool
---@param chat CodeCompanion.Chat
---@param tool CodeCompanion.Tool
---@return nil
local function set_autocmds(chat, tool)
  local ns_id = api.nvim_create_namespace("CodeCompanionAgentVirtualText")
  local group = "CodeCompanionAgent_" .. chat.bufnr

  api.nvim_create_augroup(group, { clear = true })

  return api.nvim_create_autocmd("User", {
    desc = "Handle responses from any agents",
    group = group,
    pattern = "CodeCompanionAgent*",
    callback = function(request)
      if request.data.bufnr ~= chat.bufnr then
        return
      end

      log:trace("Tool finished event: %s", request)
      if request.match == "CodeCompanionAgentStarted" then
        return ui.set_virtual_text(chat.bufnr, ns_id, "Tool processing ...", { hl_group = "CodeCompanionVirtualText" })
      end

      api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)

      if request.data.status == "error" then
        chat:append_to_buf({
          role = config.strategies.chat.roles.user,
          content = tool.output_error_prompt(request.data.error),
        })

        if config.strategies.agent.tools.opts.auto_submit_errors then
          chat:submit()
        end
      end

      if request.data.status == "success" then
        local output
        -- Sometimes, the output from a command will get sent to stderr instead
        -- of stdout. We can do a check and redirect the output accordingly
        if #request.data.output > 0 then
          output = request.data.output
        else
          output = request.data.error
        end
        chat:append_to_buf({
          role = config.strategies.chat.roles.user,
          content = tool.output_prompt(output),
        })
        if tool.opts and tool.opts.hide_output then
          chat:conceal("tool")
        end
        if config.strategies.agent.tools.opts.auto_submit_success then
          chat:submit()
        end
      end

      api.nvim_clear_autocmds({ group = group })
    end,
  })
end

local function run_agent(chat, tool, xml)
  set_autocmds(chat, tool)

  if type(tool.execute) == "function" then
    return tool.execute(chat, xml.parameters.inputs)
  else
    local env = type(tool.env) == "function" and tool.env(xml) or {}
    local cmds = type(tool.override_cmds) == "function" and tool.override_cmds(vim.deepcopy(tool.cmds))
      or vim.deepcopy(tool.cmds)

    if type(tool.pre_cmd) == "function" then
      tool.pre_cmd(env, xml)
    end

    require("codecompanion.utils.util").replace_placeholders(cmds, env)
    return require("codecompanion.tools.job_runner").init(cmds, chat)
  end
end

---Run the tool
---@param chat CodeCompanion.Chat
---@param ts table
---@return nil| CodeCompanion.ToolExecuteResult
function M.run(chat, ts)
  local ok, xml = pcall(parse_xml, ts)
  if not ok then
    log:error("Error parsing XML: %s", xml)
    return
  end

  -- FIX: This needs to work for a user's custom callback
  local ok, tool = pcall(require, "codecompanion.tools." .. xml.name)
  if not ok then
    log:error("Error loading tool: %s", tool)
    return
  end

  return run_agent(chat, tool, xml)
end

return M
