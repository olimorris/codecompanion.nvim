local config = require("codecompanion.config")
local utils = require("codecompanion.utils.adapters")

local M = {}

---Replace roles in the messages with the adapter's defined roles
---@param adapter table
---@param messages table
---@return table
function M.map_roles(adapter, messages)
  return utils.map_roles(adapter.roles, messages)
end

return M
