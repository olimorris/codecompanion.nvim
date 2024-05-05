local handler = require("codecompanion.utils.xml.xmlhandler.tree")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local M = {}

function M.run(bufnr, tools)
  local parser = xml2lua.parser(handler)
  parser:parse(tools)

  for i, p in pairs(handler.root.tool) do
    print(i, p)
  end
end

return M
