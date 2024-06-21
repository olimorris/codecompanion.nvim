local Adapter = require("codecompanion.adapter")

local M = {}

---@param adapter table
---@param opts table
---@return table
local function setup(adapter, opts)
  return vim.tbl_deep_extend("force", {}, adapter, opts or {})
end

---@param adapter string|table
---@param opts? table
---@return CodeCompanion.Adapter
function M.use(adapter, opts)
  local adapter_config

  if type(adapter) == "string" then
    adapter_config = require("codecompanion.adapters." .. adapter)
  elseif type(adapter) == "table" then
    adapter_config = adapter
  end

  if opts then
    adapter_config = setup(adapter_config, opts)
  end

  return Adapter.new(adapter_config)
end

return M
