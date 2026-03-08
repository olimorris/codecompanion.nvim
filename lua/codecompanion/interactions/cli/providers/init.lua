local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

---Resolve a provider path to the correct module
---@param path string The module or file path
---@return table|nil
local function _resolve(path)
  local ok, provider = pcall(require, "codecompanion." .. path)
  if ok then
    return provider
  end

  -- Try loading from the user's config using a module path
  ok, provider = pcall(require, path)
  if ok then
    return provider
  end

  -- Try loading from the user's config using a file path
  local err
  provider, err = loadfile(vim.fs.normalize(path))
  if err then
    return log:error("Could not load CLI provider: %s", path)
  end

  if provider then
    return provider()
  end
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
