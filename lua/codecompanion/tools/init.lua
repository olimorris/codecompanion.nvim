local handler = require("codecompanion.utils.xml.xmlhandler.tree")
local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local M = {}

function M.run(bufnr, tools)
  local parser = xml2lua.parser(handler)
  parser:parse(tools)

  log:debug("Parsed xml: %s", handler.root)

  local xml = handler.root.tool

  local ok, tool = pcall(require, "codecompanion.tools." .. xml.name)
  if not ok then
    log:error("Tool not found: %s", xml.name)
    return
  end

  tool.run(bufnr, xml)
end

return M
