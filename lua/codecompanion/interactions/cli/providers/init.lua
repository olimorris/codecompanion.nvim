local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

local M = {}

---Resolve a provider path to the correct module
---@param path string The module or file path
---@return table|nil
local function _resolve(path)
  return utils.resolve({ value = path, source = "CLI Providers" })
end

---Create a provider based on the agent's configured provider
---@param args { bufnr: number, agent: table }
---@return CodeCompanion.CLI.Provider|nil
function M.new(args)
  local provider_name = args.agent.provider or "terminal"
  local provider_config = config.interactions.cli.providers[provider_name]
  if not provider_config then
    provider_config = config.interactions.cli.providers.terminal
  end

  local provider = _resolve(provider_config.path)
  if not provider then
    return nil
  end

  return provider.new(args)
end

return M
