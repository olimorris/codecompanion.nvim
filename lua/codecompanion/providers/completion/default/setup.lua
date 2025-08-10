local M = {}

---Setup function for default completion provider
---@param config table The codecompanion configuration
function M.setup(config)
  -- The omnifunc is set per-buffer in the chat init.lua
  -- This setup function exists for consistency with other providers
  return true
end

return M