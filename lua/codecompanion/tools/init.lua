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

  vim.api.nvim_create_autocmd("User", {
    desc = "Handle the tool finished event",
    pattern = "CodeCompanionToolFinished",
    callback = function(request)
      log:debug("Tool finished event: %s", request)

      if request.buf ~= chat.bufnr then
        return
      end

      chat:add_message({
        role = "user",
        content = "After the tool completed, the output was: `"
          .. request.data.output
          .. "`. Is that what you expected?",
      })
      chat:submit()
    end,
  })

  tool.run(chat.bufnr, xml)
end

return M
