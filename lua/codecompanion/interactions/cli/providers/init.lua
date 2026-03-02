local M = {}

---Create a provider based on the configured type
---@param args { bufnr: number, agent: table }
---@return CodeCompanion.CLI.Provider
function M.new(args)
  return require("codecompanion.interactions.cli.providers.terminal").new(args)
end

return M
