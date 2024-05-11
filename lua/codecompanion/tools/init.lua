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
      log:trace("Tool finished event: %s", request)
      if request.data.status == "started" then
        ui.set_virtual_text(chat.bufnr, ns_id, "Tool processing ...")
        return
      end

      if request.buf ~= chat.bufnr or request.data.status == "error" then
        api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)
        api.nvim_clear_autocmds({ group = group })
        return
      end

      if request.data.status == "success" then
        api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)

        chat:add_message({
          role = "user",
          content = tool.output(request.data.output),
        })
        chat:submit()

        api.nvim_clear_autocmds({ group = group })
      end
    end,
  })
end

---Run the tool
---@param chat CodeCompanion.Chat
---@param ts table
---@return nil
function M.run(chat, ts)
  -- Parse the XML
  local xml = parse_xml(ts)

  -- Load the tool
  local ok, tool = pcall(require, "codecompanion.tools." .. xml.name)
  if not ok then
    log:error("Tool not found: %s", xml.name)
    return
  end

  -- Set the autocmds which will be called on closing the job
  set_autocmds(chat, tool)

  -- Run the pre_cmds
  local pre_cmds = tool.pre_cmd(xml)
  local cmds = vim.deepcopy(tool.cmds.default)
  utils.replace_placeholders(cmds, pre_cmds)

  -- Run the tool's cmds
  log:debug("Running cmd: %s", cmds)
  return require("codecompanion.tools.job_runner").run(cmds)
end

return M
