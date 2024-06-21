local config = require("codecompanion").config
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils.util")

local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local M = {}

---Parse the Tree-sitter output into XML
---@param tools table
---@return table
local function parse_xml(tools)
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  parser:parse(tools)

  log:trace("Parsed xml: %s", handler.root)

  return handler.root.tool
end

---Set the autocmds for the tool
---@param chat CodeCompanion.Chat
---@param tool CodeCompanion.Tool
---@return nil
local function set_autocmds(chat, tool)
  local ns_id = api.nvim_create_namespace("CodeCompanionToolVirtualText")
  local group = "CodeCompanionTool_" .. chat.bufnr

  api.nvim_create_augroup(group, { clear = true })

  return api.nvim_create_autocmd("User", {
    desc = "Handle responses from any tools",
    group = group,
    pattern = "CodeCompanionTool",
    callback = function(request)
      if request.data.bufnr ~= chat.bufnr then
        return
      end

      log:trace("Tool finished event: %s", request)
      if request.data.status == "started" then
        ui.set_virtual_text(chat.bufnr, ns_id, "Tool processing ...", { hl_group = "CodeCompanionVirtualTextTools" })
        return
      end

      api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)

      if request.data.status == "error" then
        chat:add_message({
          role = "user",
          content = tool.output_error_prompt(request.data.error),
        })

        if config.tools.opts.auto_submit_errors then
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
          content = tool.output_prompt(output),
        })
        chat:submit()
      end

      api.nvim_clear_autocmds({ group = group })
    end,
  })
end

---Run the tool
---@param chat CodeCompanion.Chat
---@param ts table
---@return nil
function M.run(chat, ts)
  -- Parse the XML
  local ok, xml = pcall(parse_xml, ts)

  if not ok then
    log:error("Failed to parse the XML: %s", xml)
    return
  end

  -- Load the tool
  local ok, tool = pcall(require, "codecompanion.tools." .. xml.name)
  if not ok then
    log:error("Tool not found: %s", xml.name)
    return
  end

  -- Set the autocmds which will be called on closing the job
  set_autocmds(chat, tool)

  -- Set the env
  local env = {}
  if type(tool.env) == "function" then
    env = tool.env(xml)
  end

  -- Overwrite any default cmds
  local cmds = vim.deepcopy(tool.cmds)
  if type(tool.override_cmds) == "function" then
    cmds = tool.override_cmds(cmds)
  end

  -- Run the pre_cmds
  if type(tool.pre_cmd) == "function" then
    tool.pre_cmd(env, xml)
  end

  -- Replace any vars
  utils.replace_placeholders(cmds, env)

  -- Run the tool's cmds
  log:debug("Running cmd: %s", cmds)
  return require("codecompanion.tools.job_runner").init(cmds, chat)
end

return M
