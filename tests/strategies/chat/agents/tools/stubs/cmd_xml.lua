local M = {}

function M.tool(name)
  return string.format([[<tools><tool name="%s"></tool></tools>]], name)
end

return M
