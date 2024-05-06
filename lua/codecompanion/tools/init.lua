local handler = require("codecompanion.utils.xml.xmlhandler.tree")
local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local M = {}

function M.run(chat, tools)
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
  vim.api.nvim_buf_set_extmark(chat.bufnr, ns_id, vim.api.nvim_buf_line_count(chat.bufnr) - 1, 0, {
    virt_text = { { "Waiting for the tool ...", "CodeCompanionVirtualText" } },
    virt_text_pos = "eol",
  })

  vim.api.nvim_create_autocmd("User", {
    desc = "Handle the tool finished event",
    pattern = "CodeCompanionToolFinished",
    callback = function(request)
      log:debug("Tool finished event: %s", request)
      vim.api.nvim_buf_clear_namespace(chat.bufnr, ns_id, 0, -1)

      if request.buf ~= chat.bufnr or request.data.status == "error" then
        return
      end

      local output = request.data.output

      if type(request.data.output) == "table" then
        output = table.concat(request.data.output, ", ")
      end

      chat:add_message({
        role = "user",
        content = "After the tool completed, the output was: `"
          .. output
          .. "`. Is that what you expected? If it is, just reply with a confirmation. If not, say so and I can plan our next step.",
      })
      chat:submit()
    end,
  })

  tool.run(chat.bufnr, xml)
  handler = nil
end

return M
