local config = require("codecompanion").config
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils.util")

local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local M = {}

---@class CodeCompanion.Agent
---@field cmd table The commands to execute
---@field schema string The schema that the LLM must use in its response to execute a agent
---@field opts? table The options for the agent
---@field prompts table The prompts to the LLM explaining the agent and the schema
---@field env fun(xml: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field pre_cmd fun(env: table, xml: table): table|nil Function to call before the cmd table is executed
---@field override_cmds fun(cmds: table): table Function to call to override the default cmds table
---@field output_error_prompt fun(error: table): string The prompt to share with the LLM if an error is encountered
---@field output_prompt fun(output: table): string The prompt to share with the LLM if the cmd is successful
---@field execute fun(chat: CodeCompanion.Chat, inputs: table): CodeCompanion.AgentExecuteResult|nil Function to execute the agent (used by Buffer Editor)

---@class CodeCompanion.AgentExecuteResult
---@field success boolean Whether the agent was successful
---@field message string The message to display to the user
---@field modified_files? table<string, string> The files that were modified by the agent

---@class CodeCompanion.AgentExecuteInputs

---Parse the Tree-sitter output into XML
---@param agents table
---@return table
local function parse_xml(agents)
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  parser:parse(agents)

  log:trace("Parsed xml: %s", handler.root)

  return handler.root.agent
end

---Set the autocmds for the agent
---@param chat CodeCompanion.Chat
---@param agent CodeCompanion.Agent
---@return nil
local function set_autocmds(chat, agent)
  local ns_id = api.nvim_create_namespace("CodeCompanionAgentVirtualText")
  local group = "CodeCompanionAgent_" .. chat.bufnr

  api.nvim_create_augroup(group, { clear = true })

  return api.nvim_create_autocmd("User", {
    desc = "Handle responses from any agents",
    group = group,
    pattern = "CodeCompanionAgent",
    callback = function(request)
      if request.data.bufnr ~= chat.bufnr then
        return
      end

      log:trace("Agent finished event: %s", request)
      if request.data.status == "started" then
        ui.set_virtual_text(chat.bufnr, ns_id, "Agent processing ...", { hl_group = "CodeCompanionVirtualTextAgents" })
        return
      end

      api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)

      if request.data.status == "error" then
        chat:add_message({
          role = "user",
          content = agent.output_error_prompt(request.data.error),
        })

        if config.agents.opts.auto_submit_errors then
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
        chat:add_message({
          role = "user",
          content = agent.output_prompt(output),
        })
        if agent.opts and agent.opts.hide_output then
          chat:conceal("agent")
        end
        if agent.opts and agent.opts.auto_submit_success then
          chat:submit()
        end
      end

      api.nvim_clear_autocmds({ group = group })
    end,
  })
end

local function run_agent(chat, agent, xml)
  set_autocmds(chat, agent)

  if type(agent.execute) == "function" then
    return agent.execute(chat, xml.parameters.inputs)
  else
    local env = type(agent.env) == "function" and agent.env(xml) or {}
    local cmds = type(agent.override_cmds) == "function" and agent.override_cmds(vim.deepcopy(agent.cmds))
      or vim.deepcopy(agent.cmds)

    if type(agent.pre_cmd) == "function" then
      agent.pre_cmd(env, xml)
    end

    require("codecompanion.utils.util").replace_placeholders(cmds, env)
    return require("codecompanion.agents.job_runner").init(cmds, chat)
  end
end

---Run the agent
---@param chat CodeCompanion.Chat
---@param ts table
---@return nil| CodeCompanion.AgentExecuteResult
function M.run(chat, ts)
  local xml = parse_xml(ts)
  local agent = require("codecompanion.agents." .. xml.name)
  return run_agent(chat, agent, xml)
end

return M
