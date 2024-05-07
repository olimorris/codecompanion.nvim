local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local M = {}

function M.run(chat, tools)
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)
  parser:parse(tools)

  log:debug("Parsed xml: %s", handler.root)

  local xml = handler.root.tool

  local ok, tool = pcall(require, "codecompanion.tools." .. xml.name)
  if not ok then
    log:error("Tool not found: %s", xml.name)
    return
  end

  local ns_id = vim.api.nvim_create_namespace("CodeCompanionToolVirtualText")
  ui.set_virtual_text(chat.bufnr, ns_id, "Tool processing ...")

  local group_name = "CodeCompanionTool_" .. chat.bufnr
  vim.api.nvim_create_augroup(group_name, { clear = true })

  vim.api.nvim_create_autocmd("User", {
    desc = "Handle responses from any tools",
    group = group_name,
    pattern = "CodeCompanionTool",
    callback = function(request)
      log:debug("Tool finished event: %s", request)
      vim.api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)

      if request.buf ~= chat.bufnr or request.data.status == "error" then
        vim.api.nvim_clear_autocmds({ group = group_name })
        return
      end

      if request.data.status == "success" then
        local output = request.data.output

        if type(request.data.output) == "table" then
          output = table.concat(request.data.output, ", ")
        end

        chat:add_message({
          role = "user",
          content = "After the tool completed, the output was: `"
            .. output
            .. "`. Is that what you expected? If it is, just reply with a confirmation. Don't reply with any code. If not, say so and I can plan our next step.",
        })
        chat:submit()

        vim.api.nvim_clear_autocmds({ group = group_name })
      end
    end,
  })

  tool.run(chat.bufnr, xml)
end

return M
